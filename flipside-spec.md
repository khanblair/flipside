# Flipside — Technical Specification

**Status:** v0.2 — as-built. Updated from the original pre-implementation draft (v0.1) to match what actually shipped. Sections that changed during implementation are marked **[as-built]**, with the original design intent preserved alongside the reason it changed.
**Platform:** macOS (Windows planned for a later phase, out of scope here)
**Distribution:** Direct (Developer ID signed + notarized), not Mac App Store — *signing/notarization not yet performed; see §11*
**Audience:** Personal tool, single user, single machine

> **Implementation status at a glance:** Phases 1–4 (§13) are substantially built and the core loop is confirmed working end-to-end — flip a window, type a note, dismiss, and the note persists encrypted and reappears. Phase 5 (signing/notarization) is scripted but unexecuted, pending Apple Developer credentials. Current test suite: 62 unit tests passing. See `CHANGELOG.md` for per-task status.

---

## 1. Summary

Flipside is a macOS utility that attaches a note card to the back of any window on the system — any app, not just Flipside's own UI. Each tracked window gets a small, always-visible corner badge. Clicking the badge plays a card-flip animation and reveals a note attached specifically to that window (or, where possible, to the document that window is showing). Clicking again flips back to reveal the real window underneath.

The core idea: turn every open window into a two-sided object — front is the app, back is your notes about it.

**[as-built]** In addition to the per-window badges, the app has a **main window** listing every tracked window, with a "Flip" button per row and access to the orphaned-notes list. This was not in the original design — v0.1 assumed a menu-bar-only accessory app with no window of its own (§5). It was added because the menu-bar status item does not render on the development machine (see §16), leaving no reliable way to see whether the app was running or to reach its controls. It has since proven useful in its own right as a way to see what's being tracked.

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

Story 1 (Chrome profiles) was the one story the original design did **not** fully satisfy — called out explicitly rather than glossed over. See §7.1.1 for the gap and the fix.

**[as-built] Story coverage now:**

| Story | Status |
|---|---|
| 1 — Chrome profiles | **Implemented, unverified.** The profile qualifier works and is unit tested, but has never been run against a live second Chrome profile (§7.1.1). Chrome also turned out to key on tab URL rather than title, which is *better* for this story than the original design assumed. |
| 2 — Docker note survives quit/relaunch | **Satisfied.** Docker keeps a static title, the easy case. |
| 3 — WhatsApp reminder | **Satisfied.** Static single-window title. |
| 4 — Two VS Code windows | **Unverified** — VS Code not observed in testing. |
| 5 — Claude desktop running list | **Satisfied** for the titled window; a second Claude window with an empty title falls to Tier 3. |
| 6 — Three Finder windows, independent notes | **Partially satisfied.** Finder is Tier 2/3, not Tier 1 as assumed — folder-titled windows work and stay independent, but untitled Finder windows fall to Tier 3 and won't reattach across relaunch. |
| 7 — Badge follows move/resize, disappears on close | **Satisfied.** |
| 8 — Notes never visible to other processes | **Satisfied by construction** — encrypted at rest, no network, no screen-recording permission requested. |

A story type not anticipated in v0.1: **high-churn titles** (Discord retitling per channel). Notes now follow the live window (§7.2), but a note taken on one channel is genuinely a different note from one taken on another, since the title *is* the identity.

---

## 5. High-Level Architecture

Flipside is a native Swift + AppKit application built on four subsystems.

**[as-built]** v0.1 described it as *menu-bar-resident* (`LSUIElement`, accessory activation policy, no Dock icon). It ships as a **regular Dock-visible app** with a main window, because the menu-bar status item does not render in the target environment (§16). The status item code is retained and still created at launch, in case that environment issue is resolved. Build layout is a **Swift Package** (`swift build` / `swift test`) rather than an Xcode project, assembled into a `.app` bundle by `scripts/make_app_bundle.sh`; this keeps the whole thing buildable and testable headlessly.

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
| **[as-built]** Window restored from minimize | `kAXWindowDeminiaturizedNotification` — v0.1 listed only the miniaturize half, leaving no way to bring a badge back |
| **[as-built]** New window created | `kAXWindowCreatedNotification` — **essential, and missing from v0.1.** `didLaunchApplicationNotification` fires *before* an app has created any windows, so enumerating at launch finds none. Without this, a relaunched app was never picked up at all |
| **[as-built]** Title changed | `kAXTitleChangedNotification` — required to keep a note attached as a window is retitled (§7.2) |
| **[as-built]** Minimized state | `kAXMinimizedAttribute` — read at enumeration so a window already minimized when first seen doesn't get a stray badge |

#### 6.2.1 Coordinate space conversion **[as-built]**

Not mentioned in v0.1, and a source of a bug where badges were placed nowhere near their windows.

The Accessibility API reports frames in **global display coordinates**: origin at the screen's **top-left**, Y increasing **downward**. AppKit's `NSWindow.setFrame`/`setFrameOrigin` expect **Cocoa screen coordinates**: origin at the **bottom-left**, Y increasing **upward**. Feeding an AX rect straight into an `NSWindow` places it at the vertically mirrored position. Every AX frame is converted before use:

```
cocoaY = NSScreen.screens[0].frame.height - axY - windowHeight
```

`NSScreen.screens[0]` is the primary screen, which is the origin of both coordinate systems.

#### 6.2.2 Periodic rescan **[as-built]**

AX notifications are not a complete record of reality: an app may not be Accessibility-ready when it launches (so observer registration silently fails), a window may be created before its app is observed, and windows can vanish without posting a destroyed notification. A 3-second rescan re-enumerates everything, adding windows that appeared and dropping ones that are gone. Tracking is therefore self-healing rather than dependent on every notification arriving.

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

### 7.1 Observed tier by app (target apps) **[as-built]**

v0.1 listed *assumed* tiers pending verification. These are now the **observed** tiers, read back from real identity keys written to the encrypted database during live use — which is a stronger check than Accessibility Inspector, since it reflects the key the app actually stored. Two of the original assumptions were wrong, and one of them (Chrome) materially changed the design (§7.1.1).

| App | Assumed (v0.1) | **Observed** | Notes |
|---|---|---|---|
| Finder | Tier 1 (likely) | **Tier 2 / Tier 3** ❌ *assumption wrong* | Finder does **not** expose the folder via the document attribute. Titled windows key on the folder name (`com.apple.finder::title::Downloads`); windows reporting no title fall to Tier 3. |
| Chrome | Tier 2 + profile gap | **Tier 1** ❌ *assumption wrong* | Chrome exposes the **tab URL** via `kAXDocumentAttribute`, e.g. `com.google.Chrome::doc::https://staging.kolaborate.africa/jobs`. This is better than assumed (URLs are more stable than titles) but it broke the profile fix — see §7.1.1. |
| Docker Desktop | Tier 2, low risk | **Tier 2** ✅ | Confirmed: `com.electron.dockerdesktop::title::kolaborate-macbook-air - Container - Docker Desktop`. |
| WhatsApp | Tier 2, low risk | **Tier 2** ✅ | Confirmed: `net.whatsapp.WhatsApp::title::WhatsApp`. Static title, as predicted. |
| Claude (desktop) | Tier 2 | **Tier 2** ✅ | Confirmed: `com.anthropic.claudefordesktop::title::Claude`. A second window with an empty title fell to Tier 3. |
| VS Code | Tier 2 | *not yet observed* | Not running during the observation sessions. The unsaved-indicator (`●`) stripping is implemented and unit tested, but unverified against the real app. |
| Discord | *not in v0.1* | **Tier 2, high churn** ⚠️ | Not anticipated in the original table. Title tracks the **active channel** (`#pod-soundwave | Kolaborate - Discord`), so it changes constantly during normal use. This is what exposed the identity-drift bug — see §7.2. |

**The general lesson:** "does this app expose a document attribute" was guessed wrong in both directions. Any app added to this table should be verified by reading back its stored identity key, not assumed.

#### 7.1.1 The Chrome profile gap

Bundle ID + title (Tier 2) cannot tell two Chrome windows in different profiles apart if their tab titles happen to match — this directly breaks Story 1 in §4. The fix, discussed and confirmed feasible during design:

- Each Chrome profile launches as its own process tree, invoked with a `--profile-directory=<Name>` command-line argument.
- Given a tracked window's owning PID, read that process's command-line arguments (e.g. via `sysctl`/`KERN_PROCARGS2` on macOS, no elevated privileges needed for a process owned by the same user) and extract the `--profile-directory` value.
- Extend the identity key for Chrome (and Chromium-based browsers generally) to include the profile directory.
- This is Chrome/Chromium-specific logic, not part of the generic Tier 1/2/3 scheme — it's a special case layered on top of the generic scheme for browser bundle IDs specifically.

This is promoted here as a **named requirement for v1**, not deferred work, since it's one of the user's explicit primary use cases (§4, Story 1). §15 has been updated to reflect this.

**[as-built] The qualifier applies to *both* tiers, not just Tier 2.** v0.1 specified this as layered on Tier 2 (`{bundle}::profile::{dir}::title::{title}`), on the assumption that Chrome was a Tier 2 app. Chrome actually resolves to **Tier 1** via the tab URL (§7.1), so a Tier-2-only qualifier was dead code — it could never take effect for the one browser it existed for, and two profiles viewing the same URL would have shared a single note. That is exactly the collision Story 1 exists to prevent, so the qualifier now scopes whichever tier applies:

```
{bundleIdentifier}::profile::{profileDirectory}::doc::{url}      # Tier 1
{bundleIdentifier}::profile::{profileDirectory}::title::{title}  # Tier 2
```

**Default-profile caveat:** Chrome omits `--profile-directory` entirely for windows on the Default profile, so `profileDirectory` resolves to `nil` for them and they produce **unqualified** keys. This is correct and keeps existing notes matching, but it means `nil` must be treated as "no profile suffix," never as an error. As of this writing the profile-scoped path is unit tested but **not verified against a live second Chrome profile**, since only the Default profile exists on the development machine.

---

### 7.2 Identity drift: following a window whose title changes **[as-built]**

Not in v0.1, and the source of the most user-visible bug found during testing.

A window's title is not fixed for the life of the window. Discord retitles itself on every channel switch; browsers retitle on tab change. The original design resolved the identity key **once**, when the window was first tracked, and never revisited it. The consequence: edits were written under whatever title was current when the window was *first seen*, while the UI showed the *current* title. Quitting and relaunching the app then produced a key from the new title, found no match, and presented a blank note — the note appeared lost, though it was intact in the database under the old key.

**As-built behaviour:** the app subscribes to `kAXTitleChangedNotification` and re-resolves identity when the title changes, migrating the note to follow the live window. Two safeguards, because `identity_key` is UNIQUE and a naive re-key destroys data:

- If the in-memory note is **empty** and a stored note already exists under the new key, the stored note is **adopted** (returning to a previously-noted title brings its note back).
- If **both** the in-memory note and the stored note have content, the note is **not** re-keyed — overwriting would destroy one of them. It stays under its existing key.

This makes Tier 2 behave as §7 intended (`last_title` is described there as "most recently seen window title" — it was never actually being maintained), but it does not make Tier 2 reliable for high-churn apps: a note attached to Discord while on one channel is keyed to that channel's title, so reopening on a different channel is genuinely a different note. That is a consequence of title-based identity, not a bug.

### 7.3 Notes are written on first edit, not on sight **[as-built]**

v0.1 implied a note row exists per tracked window. In practice every window ever seen got a row immediately, including a freshly-minted `session::<uuid>` row for each untitled window **on every rescan** — real usage accumulated 13 empty session rows out of 39 total within a single session, which also made the orphaned-notes list (§12 item 1) meaningless.

A note is now created in memory when a window is tracked, but only written to the database once its body is non-empty. Behaviour is otherwise identical: an unwritten empty note simply isn't found on the next launch, and a fresh empty one is created.

## 8. Overlay & Flip Renderer

### 8.1 Two overlay windows per tracked target

1. **Badge window** — small (approx. 24×24pt), borderless, always-on-top `NSWindow` pinned to a corner of the tracked window. Repositioned on every `kAXMovedNotification` / `kAXResizedNotification`. This is the only UI visible when the note is not flipped open.
2. **Card window** — full-size borderless `NSWindow`, same frame as the tracked window, shown only during and after a flip. Contains the note text view.

**[as-built] The card window must opt back into keyboard focus.** `NSWindow.canBecomeKey` returns `false` for `.borderless` windows, and a window that never becomes key never receives key events — the note card showed a caret but silently swallowed everything typed. The card uses an `NSWindow` subclass overriding `canBecomeKey`/`canBecomeMain`, and is shown with `makeKeyAndOrderFront` plus `NSApp.activate`, since the target app is frontmost at the moment the badge is clicked.

**[as-built] The card needs its own dismiss control.** The card spans the tracked window's full frame, which includes the corner the badge sits in — so the card covers the badge that opened it. Without a way out from the card itself, a flipped window was a dead end. The card header carries a **Done** button, Escape also dismisses, and the badge is re-ordered above the card after a flip.

**[as-built] Degenerate frames are filtered.** AX reports plenty of zero-size, offscreen, and oversized windows. Frames are clamped to the screen they mostly occupy, and windows too small or entirely offscreen get no overlay at all rather than an invisible or sprawling one.

### 8.2 Flip animation

- Implemented with `CATransform3D`, rotating the card window's root layer around the Y axis.
- Perspective is applied via the `m34` component of the transform (standard trick: `transform.m34 = -1.0 / distance`).
- Animation duration target: 300–400ms, eased (e.g. `kCAMediaTimingFunctionEaseInEaseOut`).
- Forward flip (badge click → note visible): card window fades/rotates in over the tracked window's frame.
- Reverse flip (note visible → badge click again): card window rotates out, badge remains.

**[as-built] Two-stage rotation, not a continuous 0°→180°.** The natural reading of the above — rotate the card's layer from 0° to 180° — settles the card facing the viewer **mirrored**: `CALayer.isDoubleSided` defaults to `true`, so past 90° the back face renders reversed rather than being culled. The note text came out backwards, which read as "the flip is broken / nothing is visible." The animation instead rotates **out to 90°** (edge-on, momentarily invisible — a real card looks the same from directly side-on whichever face you started from), swaps content at that exact midpoint, then rotates **back to identity**. The settled state is always right-side-up, whichever direction triggered it.

Doing a true two-faced flip (a proxy "front" face showing the real window, back face showing the note) would require capturing the target window's pixels, which is explicitly a non-goal (§3, §9.4).

### 8.3 What is and isn't flipped

The animation rotates Flipside's own card window, not the target application's actual window — Flipside has no access to another process's rendering pipeline. Visually, this is indistinguishable from "the window itself flipped," since the card window is sized and positioned to exactly match the target. See §12.4 for an optional future enhancement using a live screenshot as the card's front face.

### 8.4 Window level

Badge and card windows use an `NSWindow.Level` above normal application windows (e.g. `.floating` or a custom level) so they render on top of the target without stealing key/main window status from other apps unnecessarily.

---

### 8.5 Full-screen apps and Spaces **[as-built]**

Barely addressed in v0.1 — §14 listed "full-screen or Spaces-switching apps" only as an untested risk. It needs real handling, because macOS full-screen is not "a bigger window": the app is moved into its **own Space**, and ordinary windows from other apps cannot appear there at all.

Three things are required, and v0.1's implicit approach got the first one backwards:

1. **`.fullScreenAuxiliary` collection behaviour** — the only sanctioned way for a window to join another app's full-screen Space. Overlays set it.
2. **Not `.canJoinAllSpaces`.** The initial implementation used it, reasoning that badges should be available everywhere. That is exactly wrong for per-window overlays: it renders *every* badge on *every* Space, so badges belonging to desktop windows float over an unrelated full-screen app, attached to nothing. Overlays now use `[.fullScreenAuxiliary, .moveToActiveSpace]`, and Space membership is decided explicitly (below).
3. **Explicit active-Space filtering.** The Accessibility API has no concept of Spaces — it reports windows from all of them simultaneously, with frames, whether or not they're on screen. So the app must determine for itself which tracked windows are currently visible. `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` provides that; a tracked window is considered on the active Space when an on-screen entry matches on owning PID and approximate frame (there is no shared identifier between `AXUIElement` and `CGWindowList`, so this correlation is a heuristic, with a few points of tolerance for the two APIs disagreeing mid-animation).

   This stays within §6.3's constraint: only `kCGWindowOwnerPID` and `kCGWindowBounds` are read, neither of which requires Screen Recording permission. Window *names* are never requested — that is the part which would.

4. **`NSWorkspace.activeSpaceDidChangeNotification`** — switching Spaces changes what's on screen without firing any AX notification, so overlays would otherwise linger over the wrong Space. Triggers a full rescan.

Additionally, frames are clamped against `NSScreen.frame` rather than `visibleFrame`: a full-screened window legitimately spans the whole screen since the menu bar auto-hides, and clamping to the menu-bar-excluding `visibleFrame` shrank its card and pushed the badge off the window's real top edge.

**Unverified.** All of the above is implemented and the Space-membership logic is unit tested, but the actual behaviour of an overlay drawn over a live full-screen app has not been confirmed on a real machine. Apple restricts this area and behaviour varies by macOS version; if `.fullScreenAuxiliary` at `.floating` level proves insufficient, raising the window level is the next step.

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

## 12. Open Questions / Deferred Decisions **[as-built: resolutions recorded]**

1. Should Tier 3 (unlinked, session-only) notes be discarded on app close, or retained and shown in a "orphaned notes" list for manual re-linking later? *(Leaning toward: retained, surfaced in a simple list.)*
   → **Resolved: retained and surfaced.** A read-only orphaned-notes window lists Tier 3 notes. Manual promotion to a Tier 2 key is **not** implemented. Note that §7.3 changed what lands here: only notes with content are stored, so the list no longer fills with empty rows.
2. Should minimized windows keep their badge visible or simply hide until the window is restored? *(Leaning toward: hide.)*
   → **Resolved: hide**, restoring on `kAXWindowDeminiaturizedNotification`. Minimizing while flipped also resets the flip state, which would otherwise leave the state machine claiming "flipped" with a hidden card.
3. Multiple displays: does the badge need per-display coordinate handling? *(Likely no extra work needed — confirm during implementation.)*
   → **Resolved: extra work *was* needed**, though not for the reason anticipated. The AX↔Cocoa coordinate conversion (§6.2.1) is essential on any setup, and frames are clamped per-screen (§8.1). **Not verified on an actual multi-display setup** — the development machine is single-display.
4. Keyboard-only flip trigger (global hotkey) — nice-to-have, not required for v1.
   → **Implemented: ⌃⌥F flips whichever window is in front.** Added after live use, because a corner badge on every window read as clutter. A plain single click on a window's title bar was considered and rejected: a single click there is how a window gets focused and how every drag starts, and in Chrome the title bar *is* the tab strip, so it would fire constantly.
   - Registered with Carbon's `RegisterEventHotKey`, not an `NSEvent` global monitor. A global monitor can only observe (the frontmost app would also receive ⌃⌥F), doesn't fire while Flipside itself is frontmost, and needs Input Monitoring permission. A registered hot key needs no permission, fires whichever app is in front, and consumes the keystroke.
   - Pressing it while a note card is open flips *that card* back. Showing a card activates Flipside so the card can take typing, which means Flipside is the frontmost app at that point, not the window the note belongs to.
   - Flipping back hands focus back to the owning app. Without this, a round trip left no window focused, and a second ⌃⌥F found Flipside frontmost with nothing to flip.
   - If another app already owns ⌃⌥F, registration fails and the main window says so rather than silently doing nothing.
   - **Unverified live:** the targeting depends on the focused-window `AXUIElement` comparing equal to the one captured during enumeration, which should hold (both resolve to the same element via `CFEqual`) but hasn't been confirmed on a real machine. Badges remain in place; hiding them is a separate decision.
5. Should note bodies support Markdown rendering, or stay plain text? *(Leaning toward: plain text now.)*
   → **Plain text**, as planned. Consistent with §3's non-goals.

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

### 13.1 Delivery status **[as-built]**

| Phase | Status |
|---|---|
| 1 — Core mechanism | **Done**, except the Accessibility Inspector audit, which was superseded: tiers were instead confirmed by reading back stored identity keys from real use (§7.1), which reflects what the app actually persists. |
| 2 — Flip + notes | **Done.** Core loop confirmed end-to-end: flip → type → dismiss → note persists and reappears. |
| 3 — Persistence | **Done.** SQLCipher, Keychain key, tiered identity, and Chrome profile detection all built; Chrome profile path unit tested but not verified against a live second profile (§7.1.1). |
| 4 — Polish | **Mostly done.** Ambiguous-match prompt, orphaned-notes list, minimize handling, and debouncing built. Multi-app/multi-window **stress testing not performed**. |
| 5 — Packaging | **Scripted, not executed.** `make_app_bundle.sh`, `notarize.sh`, `build_dmg.sh` exist; DMG build verified. Signing and notarization require Apple Developer credentials and have not been run — the app currently ships ad-hoc signed, which has real consequences (§16). |

---

## 14. Risks

| Risk | Impact | Mitigation | **[as-built] Outcome** |
|---|---|---|---|
| Some apps expose incomplete or misleading Accessibility trees | Titles/documents not readable for those apps | Tier 3 fallback (session-only, user-visible as unlinked) | **Materialized, as predicted.** Many windows (untitled Finder windows, widget hosts) fall to Tier 3. The Finder and Chrome tier assumptions were also both wrong (§7.1). |
| Accessibility grant lost on rebuild during development | Repeated permission re-prompts, dev friction | Consistent Developer ID signing from early on | **Materialized, and the mitigation was unavailable** — no Developer ID credentials, so every rebuild is ad-hoc signed with a content-derived identity, and macOS treats each build as a different app. This caused repeated "the app stopped tracking windows" confusion. `scripts/uninstall.sh` clears stale grants; a real Developer ID signature is the only actual fix. |
| Rapid window churn | Badge/card windows could lag or leak | Debounce AXObserver callbacks; tear down on `kAXUIElementDestroyedNotification` | **Mitigated.** Debouncing built. A related bug appeared and was fixed: frame updates fired for *every* tracked window on *any* window's move/resize, resetting the card mid-flip. Frame updates are now skipped when unchanged. |
| Full-screen or Spaces-switching apps | Badge could be misplaced across Spaces | Test explicitly in Phase 4 | **Materialized, and the original approach was backwards.** `.canJoinAllSpaces` showed every badge on every Space rather than confining each to its window's own. Now handled explicitly — see §8.5. Still unverified against a live full-screen app. |
| **[new, unforeseen]** Menu-bar status item may not render at all | No menu-bar entry point; app appears not to be running | Main window + Dock icon as the primary entry point | **Materialized.** See §16. |

---

## 15. Explicitly Out of Scope for This Document

- Windows support (will be a separate spec; HWND-based tracking, DPAPI/Credential Manager for key storage, and Win32 overlay windows replace the AppKit/Accessibility-specific sections above).
- Browser-profile-aware notes for browsers **other than** Chrome/Chromium (e.g. Safari, Firefox profile detection uses a different mechanism and is not covered by §7.1.1).
- Any cloud sync, backup, or multi-device story.

---

## 16. Environment deviations & unresolved issues **[as-built]**

New section. These are conditions of the actual target machine that changed the design, rather than choices.

### 16.1 The menu-bar status item does not render

On the development machine (macOS 26.6.2, Apple Silicon), an `NSStatusItem` created by this app **never becomes visible**, despite AppKit reporting success at every step — `NSStatusItemScene` is created and the FrontBoard/Control Center scene handshake completes with no errors logged.

This was isolated with a **minimal standalone test app** unrelated to Flipside's codebase: a bright red status item labelled `TEST123` was equally invisible. A regular bordered `NSWindow` from the same process rendered normally. So this is not a Flipside bug and not a general windowing failure — it is specific to Control-Center-hosted status items in this environment. Root cause unknown; the leading hypothesis is a restriction on status items from ad-hoc-signed processes, which would make it a downstream consequence of §14's signing risk, but **this is unverified**.

**Consequence:** the app ships Dock-visible with a main window (§1, §5). The status item code remains in place, so if the underlying cause is resolved (most plausibly by signing with a real Developer ID), the menu-bar entry point should start working with no further changes.

### 16.2 Ad-hoc signing consequences

Without Developer ID credentials the app is ad-hoc signed, and the signature is derived from binary content — so **every rebuild is a different identity to macOS**. This means:

- Accessibility permission may need re-granting after a rebuild, and stale entries accumulate in System Settings (`scripts/uninstall.sh` clears them).
- `spctl` assesses the app as rejected; Gatekeeper may require an explicit "Open Anyway" on first launch of a build.
- `install_name_tool` (used to bundle SQLCipher) invalidates the signature, so the bundle **must** be re-signed afterwards or macOS kills it at launch with `Code Signature Invalid`. `make_app_bundle.sh` does this.

### 16.3 Known-unverified areas

Listed plainly so they aren't mistaken for tested behaviour:

- Chrome per-profile notes — unit tested, never run against a live second Chrome profile.
- Multi-display behaviour — single-display development machine only.
- Full-screen / Spaces behaviour — untested.
- Multi-window stress testing (Phase 4) — not performed.
- VS Code tier and its unsaved-indicator title stripping — implemented, never observed against the real app.
- Signing and notarization — scripted, never executed.
