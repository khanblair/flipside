# Flipside — Technical Specification

**Status:** Draft v0.1
**Platform:** macOS (Windows planned for a later phase, out of scope here)
**Distribution:** Direct (Developer ID signed + notarized), not Mac App Store
**Audience:** Personal tool, single user, single machine

---

## 1. Summary

Flipside is a macOS utility that attaches a note card to the back of any window on the system — any app, not just Flipside's own UI. Each tracked window gets a small, always-visible corner badge. Clicking the badge plays a card-flip animation and reveals a note attached specifically to that window (or, where possible, to the document that window is showing). Clicking again flips back to reveal the real window underneath.

The core idea: turn every open window into a two-sided object — front is the app, back is your notes about it.

---

## 2. Goals

- Attach a persistent note to **any** window belonging to **any** running application, without modifying that application.
- Make notes survive the app being quit and relaunched, when the underlying document/context can be identified.
- Keep each window's notes fully isolated — no cross-window leakage, no shared global note pool.
- Local-first: no cloud sync, no account, no network dependency for core functionality.
- Encrypt notes at rest.
- Low-friction capture: one click to flip, start typing immediately.

## 3. Non-Goals (v1)

- Cross-device sync.
- Multi-user collaboration or sharing.
- Windows/Linux support (tracked as a future phase; architecture should not preclude it, but nothing here is built for it yet).
- Rich text / images / checklists inside notes (v1 is plain text; formatting is a later enhancement).
- Mac App Store distribution.
- Capturing or displaying the real window's pixel content as part of the flip (see §9.4 for the optional future enhancement).

---

## 4. User Stories

1. As the user, I have Chrome open in two profiles side by side (Profile 1 for personal, Profile 2 for work). I flip a note on the Profile 2 window to jot down a task URL. When I later flip the Profile 1 window with a similarly-titled tab, I expect a **different, empty** note — not the Profile 2 content. *(This requires profile-aware identity, not just bundle ID + title — see §7.1.)*
2. As the user, I flip a note on Docker Desktop while a container is misbehaving, to record what I've already tried before restarting it. I quit Docker Desktop entirely; when I reopen it later, my note is still there.
3. As the user, I flip a note on WhatsApp to leave myself a reminder about a conversation I need to follow up on, without it cluttering the chat itself or being visible to anyone I'm messaging.
4. As the user, I have two VS Code windows open on two different projects. Each keeps its own separate notes, correctly reattached even after I close and reopen that project's window — as long as the project folder is still reflected in the window title.
5. As the user, I flip a note on my Claude desktop window to keep a running list of follow-up questions while I work, separate from the conversation itself.
6. As the user, I have three Finder windows open on three different project folders. Each has its own independent notes — flipping one never shows another's content.
7. As the user, I want the badge to stay correctly positioned on each of these windows as I move or resize it, and to disappear when the window closes.
8. As the user, I never want Flipside notes visible to any other process, screen-recording app, or synced service.

### 4.1 Coverage note

Story 1 (Chrome profiles) is the one story in this list the current design does **not** fully satisfy yet — it's called out explicitly rather than glossed over. See §7.1 for the gap and the fix.

---

## 5. High-Level Architecture

Flipside is a native Swift + AppKit menu-bar-resident application built on four subsystems:

```
┌─────────────────────────────────────────────────────────┐
│                     Flipside.app                         │
│                                                           │
│  ┌───────────────┐   ┌───────────────┐   ┌────────────┐ │
│  │ Window         │   │ Overlay &      │   │ Storage    │ │
│  │ Tracker        │──▶│ Flip Renderer  │   │ Layer      │ │
│  │ (Accessibility │   │ (AppKit/Core   │   │ (SQLite +  │ │
│  │  API)          │   │  Animation)    │   │  SQLCipher)│ │
│  └───────────────┘   └───────────────┘   └────────────┘ │
│          │                                     ▲          │
│          ▼                                     │          │
│  ┌───────────────┐                    ┌────────────────┐ │
│  │ Identity       │───────────────────▶│ Key Resolver   │ │
│  │ Resolver       │                    │ (macOS         │ │
│  │ (bundle ID +   │                    │  Keychain)     │ │
│  │  doc path /    │                    └────────────────┘ │
│  │  title)        │                                       │
│  └───────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

No components run outside the app process. No network calls.

---

## 6. Window Tracker

### 6.1 Responsibilities

- Enumerate windows of every running application at launch.
- Detect new applications launching and new windows being created.
- Track window move, resize, minimize, and close events for every tracked window.
- Expose a live list of `(pid, AXUIElement, frame, title, bundleID)` tuples to the rest of the app.

### 6.2 APIs used

| Need | API |
|---|---|
| Enumerate an app's windows | `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute` |
| Window title | `kAXTitleAttribute` |
| Window position / size | `kAXPositionAttribute`, `kAXSizeAttribute` |
| Open document path (when available) | `kAXDocumentAttribute` |
| Move/resize/close notifications | `AXObserver` + `kAXMovedNotification`, `kAXResizedNotification`, `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification` |
| New app launched/quit | `NSWorkspace.shared.notificationCenter` (`didLaunchApplicationNotification`, `didTerminateApplicationNotification`) |

### 6.3 Explicitly not used

- `CGWindowListCopyWindowInfo` / `ScreenCaptureKit` for window titles or content — not needed for v1, and would require the separate Screen Recording permission. Accessibility alone is sufficient for title, frame, and document path.

### 6.4 Permission requirement

Flipside requires **Accessibility** permission (System Settings → Privacy & Security → Accessibility), requested via `AXIsProcessTrustedWithOptions` with the prompt option enabled, with an `NSAccessibilityUsageDescription` string in `Info.plist` explaining why.

This is the only TCC permission required for v1.

**Known gotcha:** macOS ties the Accessibility grant to the specific signed binary. Debug builds signed ad hoc or with a changing identity will periodically lose the grant and require re-approval. Use a consistent Developer ID signing identity from early in development to avoid repeated re-grants.

---

## 7. Window Identity & Persistence

Process IDs and `AXUIElement` references are only valid for the life of a running process — they cannot be used as a persistent key. Identity is resolved in tiers, from most to least stable:

**Tier 1 — Bundle ID + document path.** When `kAXDocumentAttribute` is available (Preview, TextEdit, Pages, and most document-based apps), the key is:

```
{bundleIdentifier}::doc::{documentPath}
```

This survives app quits, relaunches, and reboots, and is the preferred key whenever available.

**Tier 2 — Bundle ID + window title.** For apps without a document attribute (Finder, Terminal, Messages, browsers), the key is:

```
{bundleIdentifier}::title::{windowTitle}
```

This is best-effort. Titles can repeat (`Untitled`, `Untitled 2`) or change over a window's lifetime. When Flipside detects an ambiguous match (more than one stored note key plausibly matches a newly appeared window), it does **not** silently guess — it prompts the user to confirm which note (if any) belongs to the new window.

**Tier 3 — Session-only.** If neither of the above is reliable (e.g. a window with a generic, frequently reused title and no document), the note is tied only to the live `AXUIElement`/PID for the current session and is explicitly flagged in the UI as "not linked to a specific window — will not reattach automatically." The user can manually promote it to a Tier 2 key.

PID and `AXUIElement` are used only for live session tracking and are never written to the database.

### 7.1 Expected tier by app (target apps)

None of these have been empirically confirmed against Accessibility Inspector yet — that's Phase 1 work (§13) — but this is the working assumption per app, based on how each typically implements the Accessibility protocol:

| App | Expected tier | Notes |
|---|---|---|
| Finder | Tier 1 (likely) | Finder windows commonly expose the folder location via the document attribute; **must be verified**, not assumed. |
| VS Code | Tier 2 | No document attribute observed in practice for editor windows; window title includes the project/folder name (e.g. `myproject — Visual Studio Code`), which is fairly stable across sessions. Unsaved-file indicators (`●`) in the title should be stripped before matching. |
| Claude (desktop) | Tier 2 | Title likely static or conversation-name-based; treat as best-effort. |
| Docker Desktop | Tier 2, low risk | Typically a single window with a static title, so title-collision risk is minimal even without a document attribute. |
| WhatsApp | Tier 2, low risk | Single-window app; static title, low collision risk. |
| Chrome (any profile) | **Tier 2, with a known gap** | See §7.1.1 below — title alone cannot distinguish two profiles. |

#### 7.1.1 The Chrome profile gap

Bundle ID + title (Tier 2) cannot tell two Chrome windows in different profiles apart if their tab titles happen to match — this directly breaks Story 1 in §4. The fix, discussed and confirmed feasible during design:

- Each Chrome profile launches as its own process tree, invoked with a `--profile-directory=<Name>` command-line argument.
- Given a tracked window's owning PID, read that process's command-line arguments (e.g. via `sysctl`/`KERN_PROCARGS2` on macOS, no elevated privileges needed for a process owned by the same user) and extract the `--profile-directory` value.
- Extend the identity key for Chrome (and Chromium-based browsers generally) to: `{bundleIdentifier}::profile::{profileDirectory}::title::{windowTitle}`.
- This is Chrome/Chromium-specific logic, not part of the generic Tier 1/2/3 scheme — it's a special case layered on top of Tier 2 for browser bundle IDs specifically.

This is promoted here as a **named requirement for v1**, not deferred work, since it's one of the user's explicit primary use cases (§4, Story 1). §15 has been updated to reflect this.

---

## 8. Overlay & Flip Renderer

### 8.1 Two overlay windows per tracked target

1. **Badge window** — small (approx. 24×24pt), borderless, always-on-top `NSWindow` pinned to a corner of the tracked window. Repositioned on every `kAXMovedNotification` / `kAXResizedNotification`. This is the only UI visible when the note is not flipped open.
2. **Card window** — full-size borderless `NSWindow`, same frame as the tracked window, shown only during and after a flip. Contains the note text view.

### 8.2 Flip animation

- Implemented with `CATransform3D`, rotating the card window's root layer around the Y axis.
- Perspective is applied via the `m34` component of the transform (standard trick: `transform.m34 = -1.0 / distance`).
- Animation duration target: 300–400ms, eased (e.g. `kCAMediaTimingFunctionEaseInEaseOut`).
- Forward flip (badge click → note visible): card window fades/rotates in over the tracked window's frame.
- Reverse flip (note visible → badge click again): card window rotates out, badge remains.

### 8.3 What is and isn't flipped

The animation rotates Flipside's own card window, not the target application's actual window — Flipside has no access to another process's rendering pipeline. Visually, this is indistinguishable from "the window itself flipped," since the card window is sized and positioned to exactly match the target. See §12.4 for an optional future enhancement using a live screenshot as the card's front face.

### 8.4 Window level

Badge and card windows use an `NSWindow.Level` above normal application windows (e.g. `.floating` or a custom level) so they render on top of the target without stealing key/main window status from other apps unnecessarily.

---

## 9. Storage Layer

### 9.1 Database

- SQLite, encrypted at rest via SQLCipher.
- Location: `~/Library/Application Support/Flipside/flipside.sqlite` (outside any sandbox container, since Flipside is unsandboxed).

### 9.2 Schema (v1)

```sql
CREATE TABLE notes (
    id            TEXT PRIMARY KEY,       -- UUID
    identity_key  TEXT NOT NULL UNIQUE,   -- see §7 tiering scheme
    identity_tier INTEGER NOT NULL,       -- 1, 2, or 3
    body          TEXT NOT NULL DEFAULT '',
    created_at    INTEGER NOT NULL,       -- unix epoch
    updated_at    INTEGER NOT NULL,
    bundle_id     TEXT NOT NULL,
    app_name      TEXT NOT NULL,          -- human-readable, for UI/debugging
    last_title    TEXT,                   -- most recently seen window title
    last_doc_path TEXT                    -- most recently seen document path, if any
);

CREATE INDEX idx_notes_bundle ON notes(bundle_id);
```

### 9.3 Encryption key

The SQLCipher key is generated once at first launch, stored in **macOS Keychain** via the Security framework (`SecItemAdd`/`SecItemCopyMatching`), and retrieved at app launch. No password prompt, no hardcoded key, no key derivation from a user-typed password.

### 9.4 Future enhancement (not v1)

Optionally capture a live thumbnail of the tracked window at flip time (via `ScreenCaptureKit`, requiring the separate Screen Recording permission) to use as the visible "front face" mid-animation, rather than a blank/generic proxy. Purely cosmetic; does not change the identity or storage model.

---

## 10. Permissions Summary

| Permission | Required for | Requested when |
|---|---|---|
| Accessibility | Window enumeration, tracking, title/frame/document reads | First launch |
| Screen Recording | Not required in v1 | N/A (only if §9.4 is built later) |
| Keychain access | Storing/retrieving the SQLCipher key | First launch (implicit, no user prompt beyond standard Keychain access dialog on first write) |

No network entitlements are requested — Flipside makes no network calls.

---

## 11. Distribution

- Signed with a Developer ID Application certificate.
- Notarized via `notarytool` as part of the build/release process.
- App Sandbox entitlement is **not** applied — sandboxed apps cannot use the Accessibility API to control other applications, with no entitlement available to unlock it, so sandboxing is fundamentally incompatible with Flipside's core feature.
- Distributed as a downloadable `.app` (e.g. as a DMG or zip) rather than through the Mac App Store.
- No auto-update mechanism in v1 (manual redownload); Sparkle or similar can be added later if useful for a personal tool with a small update cadence.

---

## 12. Open Questions / Deferred Decisions

1. Should Tier 3 (unlinked, session-only) notes be discarded on app close, or retained and shown in a "orphaned notes" list for manual re-linking later? *(Leaning toward: retained, surfaced in a simple list.)*
2. Should minimized windows keep their badge visible (e.g. shrunk into the Dock icon region) or simply hide until the window is restored? *(Leaning toward: hide, simplest for v1.)*
3. Multiple displays: does the badge need per-display coordinate handling beyond what `AXPosition` already returns in global screen coordinates? *(Likely no extra work needed — confirm during implementation.)*
4. Keyboard-only flip trigger (global hotkey on the frontmost window) in addition to badge click — nice-to-have, not required for v1.
5. Should note bodies support Markdown rendering, or stay plain text for v1 simplicity? *(Leaning toward: plain text now, Markdown preview later.)*

---

## 13. Phased Delivery Plan

**Phase 1 — Core mechanism**
- Accessibility permission flow.
- Window enumeration + live tracking (move/resize/close) for a single test app.
- Badge overlay rendering and repositioning.
- Run Accessibility Inspector (Xcode → Open Developer Tool) against each target app in §7.1 (Finder, VS Code, Claude, Docker Desktop, WhatsApp, Chrome) to confirm actual tier per app, replacing the assumed values in that table.

**Phase 2 — Flip + notes**
- Card overlay window and 3D flip animation.
- Plain-text note editing, in-memory only (no persistence yet).

**Phase 3 — Persistence**
- SQLite + SQLCipher integration.
- Keychain key storage/retrieval.
- Tier 1/2/3 identity resolution and matching on window reappearance.
- Chrome/Chromium profile detection via `--profile-directory` process-argument lookup (§7.1.1).

**Phase 4 — Polish**
- Ambiguous-match confirmation UI.
- Orphaned/Tier 3 notes list.
- Multi-app, multi-window stress testing (many windows open simultaneously, rapid open/close cycles).

**Phase 5 — Packaging**
- Developer ID signing, notarization, DMG build script.

---

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Some apps expose incomplete or misleading Accessibility trees | Titles/documents not readable for those apps | Tier 3 fallback (session-only, user-visible as unlinked) |
| Accessibility grant lost on rebuild during development | Repeated permission re-prompts, dev friction | Consistent Developer ID signing from early on |
| Rapid window churn (many opens/closes in quick succession, e.g. browser tabs opening as new windows) | Badge/card windows could lag or leak | Debounce AXObserver callbacks; explicitly tear down overlays on `kAXUIElementDestroyedNotification` |
| Full-screen or Spaces-switching apps | Badge could be misplaced across Spaces | Test explicitly in Phase 4; may need per-Space window level handling |

---

## 15. Explicitly Out of Scope for This Document

- Windows support (will be a separate spec; HWND-based tracking, DPAPI/Credential Manager for key storage, and Win32 overlay windows replace the AppKit/Accessibility-specific sections above).
- Browser-profile-aware notes for browsers **other than** Chrome/Chromium (e.g. Safari, Firefox profile detection uses a different mechanism and is not covered by §7.1.1).
- Any cloud sync, backup, or multi-device story.
