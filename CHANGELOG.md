# Flipside — Changelog / Implementation Checklist

Tracks implementation status against [flipside-spec.md](flipside-spec.md) (kept in sync — the spec is now at v0.2 "as-built"). **Current status: 62/62 unit tests passing** (`swift test`), full package + `.app` bundle assembly build clean, and the **core loop is confirmed working end-to-end**: flip a window, type a note, dismiss, and the note persists encrypted and reappears. Each item is marked:

- `[ ]` not started
- `[~]` implemented, not yet runtime-verified (compiles / builds, but needs a live GUI session with Accessibility permission granted, or Apple Developer credentials, to actually exercise)
- `[x]` implemented and verified (unit tests passing, or manually confirmed)

## Decisions locked in for implementation

- **Project format:** Swift Package Manager, not a hand-authored `.xcodeproj` — lets `swift build` / `swift test` run headlessly for real verification. A `.app` bundle is produced at packaging time (Phase 5) from the SPM executable.
- **SQLCipher integration:** real SQLCipher via the official Homebrew-core `sqlcipher` formula (`brew install sqlcipher`), linked through an SPM system-library target (`CSQLCipher`) via pkg-config — not a hand-vendored amalgamation, not a substitute encryption scheme.
- **Chromium bundle-ID set:** seeded with only `com.google.Chrome`, per the spec's target-app table (§7.1).
- **Ambiguous-match candidate rule:** conservative default — Tier 1 is unambiguous by construction; Tier 2 candidates are same-bundle notes whose stored title matches a generic-title pattern (`Untitled`, `Untitled N`, etc.). Not spec-mandated; confirm before Phase 4 ships.
- **Open Questions §12:** follows the spec's own stated leanings — orphaned Tier-3 notes retained and surfaced (#1), badge hides on minimize (#2).
- **macOS deployment target:** 14.0 (Sonoma or later).
- **Activation policy:** ships `.regular` (Dock icon + main window), *not* the menu-bar-only accessory app the spec originally described — the menu-bar status item doesn't render in this environment (spec §16.1). Status item code retained in case that resolves.
- **Chrome profile qualifier scopes both tiers**, not just Tier 2 as spec v0.1 said — Chrome resolves to Tier 1 via the tab URL, so a Tier-2-only qualifier was dead code (spec §7.1.1).
- **Notes are written on first edit, not on sight** — avoids accumulating empty rows per window per scan (spec §7.3).

## Phase 1 — Core Mechanism

- [x] Task 1 — Project scaffolding (`Info.plist`, no-sandbox entitlements) — `swift build` passes. **Changed since:** ships `.regular` (Dock icon + main window), not the menu-bar-only shell originally planned (spec §16.1).
- [x] Task 2 — Accessibility permission flow — **live-verified**: prompt appears, and once granted the app enumerates real windows. Caveat: each ad-hoc rebuild is a new identity to macOS, so the grant often needs reapplying per build (spec §16.2).
- [x] Task 3 — `TrackedWindow` + `WindowRegistry` (pure logic, unit tested) — 7/7 tests passing
- [x] Task 4 — `AXWindowReader` + `WindowTracker` live enumeration — **live-verified on the user's machine**: 13 real windows correctly enumerated across Finder, Chrome, Discord, Docker Desktop, WhatsApp, System Settings, and Notification Center, once Accessibility permission was actually granted for the current build
- [x] Task 5 — AXObserver + NSWorkspace live notifications — **live-verified**, and extended well beyond the original scope after real-use bugs: added `kAXWindowCreatedNotification` (without it a relaunched app was *never* picked up, since the launch notification fires before any window exists), `kAXWindowDeminiaturizedNotification`, `kAXTitleChangedNotification`, and a 3s self-healing rescan (spec §6.2, §6.2.2).
- [x] Task 6 — Badge overlay window — **live-verified visible on tracked windows.** Took four separate fixes to get there: a double-release crash, the AX↔Cocoa coordinate conversion, degenerate-frame filtering, and finally the initial-visibility bug (badge visibility was routed through `setMinimized()`, whose no-change guard short-circuited for non-minimized windows, so badges only appeared after a flip).
- [x] Task 7 — Per-app tier audit — **done by a better method than planned.** Rather than Accessibility Inspector, tiers were confirmed by reading back identity keys actually written to the encrypted DB during real use, which reflects what the app truly persists. Two v0.1 assumptions were wrong: **Finder is Tier 2/3, not Tier 1**, and **Chrome is Tier 1 (tab URL via `kAXDocumentAttribute`), not Tier 2** — the latter invalidated the original Chrome profile design. Full table in spec §7.1.

## Phase 2 — Flip + Notes

- [x] Task 8 — Card overlay window — **live-verified.** Needed two fixes beyond the original design: borderless windows can't become key (so typing was silently swallowed until a `canBecomeKey` override was added), and the card covers the badge that opened it (so it needed its own Done button + Escape). Restyled as a Keep-like note with placeholder text (spec §8.1).
- [x] Task 9 — `FlipTransform` — pure `CATransform3D` math (unit tested) — 3/3 tests passing
- [x] Task 10 — `FlipStateMachine` — pure front/back state (unit tested) — 2/2 tests passing
- [x] Task 11 — Wire badge click → flip → card show/hide — **live-verified end-to-end.** Animation reworked from a continuous 0°→180° rotation (which settles *mirrored*, rendering the note backwards) to a two-stage out-to-90°/back-to-identity flip (spec §8.2).

## Phase 3 — Persistence

- [x] Task 12 — SQLCipher-backed `Database` wrapper + schema (unit tested: wrong key cannot read the file) — 2/2 tests passing
- [x] Task 13 — `KeychainKeyStore` (unit tested: round-trip, idempotent create) — 3/3 tests passing
- [x] Task 14 — `Note` model + `NoteRepository` (unit tested: upsert/find, conflict resolution) — 4/4 tests passing
- [x] Task 15 — `IdentityKeyBuilder` — Tier 1/2/3 (unit tested, incl. VS Code title normalization) — 10/10 tests passing
- [x] Task 16 — `ChromeProfileResolver` — `--profile-directory` extraction (unit tested pure core; syscall parsing additionally verified empirically against live Chrome PIDs on this machine) — 3/3 tests passing. **Finding:** default-profile Chrome windows carry no `--profile-directory` flag at all — `profileDirectory(forPID:)` returns `nil` for them; downstream identity-key logic must treat `nil` as "no profile suffix, use plain Tier 2," not as an error.
- [x] Task 17 — `AmbiguousMatchDetector` (unit tested, all three outcomes) — 3/3 tests passing
- [x] Task 18 — Wire persistence into the overlay coordinator — **live-verified**: notes survive quitting and reopening the app. Two significant post-verification fixes: **identity drift** (the key was resolved once at creation and never updated, so notes for retitling apps like Discord were written under stale keys and appeared lost — now follows the window via title-change notifications, with safeguards so two non-empty notes can never overwrite each other, spec §7.2), and **notes are now written on first edit rather than on sight** (spec §7.3).

## Phase 4 — Polish

- [~] Task 19 — Ambiguous-match confirmation UI — `AmbiguousMatchPrompt` (modal `NSAlert`) wired into `OverlayCoordinator`'s `.ambiguous` case; compiles, not unit-testable (no way to drive a real modal loop headlessly), needs a live GUI session to verify
- [~] Task 20 — Orphaned / Tier 3 notes list — `NoteRepository.allNotes(tier:)` is unit tested (1/1 passing); `OrphanedNotesWindowController` + status-bar menu item compile, needs a live GUI session to verify. Read-only for v1 — manual promotion to a Tier-2 key (spec §7's "the user can manually promote it") is not implemented.
- [x] Task 21 — `Debouncer` utility, wired into `WindowTracker`'s move/resize AX callbacks (destroy notifications stay immediate) — 2/2 unit tests passing
- [~] Task 22 — Minimized-window badge hide/restore — unit tested; wiring now also resets flip state when minimizing while flipped (which otherwise left the state machine claiming 'flipped' with a hidden card). Live minimize/restore still unverified.
- [ ] Task 23 — Multi-window stress test pass (investigation) — not started, needs a human at the machine

## Phase 5 — Packaging

- [~] Task 24 — Signing & entitlements audit — `scripts/make_app_bundle.sh` verified: assembles a real self-contained `.app` (bundled `libsqlcipher.dylib`, `@rpath` rewritten and confirmed via `otool -L`/`otool -l`), entitlements file has no sandbox key; actual `codesign` with a Developer ID identity needs credentials not available here
- [~] Task 25 — Notarization script — written (`scripts/notarize.sh`), not executed; requires the user's own Apple Developer ID certificate + notarytool credentials
- [x] Task 26 — DMG build script — `scripts/build_dmg.sh` run end-to-end against a built bundle; `hdiutil verify` passed

## Post-review fixes (found while first launching the built app)

- **App was being silently killed within ~1 minute of launch.** Root cause: Flipside is menu-bar-only with no regular window, and AppKit's automatic-termination feature treats that as "idle" and reaps it in the background (confirmed via the unified log — `_kLSApplicationWouldBeTerminatedByTALKey=1` shortly after launch). Fixed with `ProcessInfo.disableAutomaticTermination(_:)` at launch. This is why Task 2/4–11 verification looked like it wasn't running at all — it *was* launching, just dying quietly with no crash report.
- **App also failed to launch at all on the very first attempt**, with `SIGKILL (Code Signature Invalid)`: `install_name_tool` (used by `make_app_bundle.sh` to bundle `libsqlcipher.dylib`, Task 24) invalidates the linker's ad-hoc signature, and macOS refuses to run a binary whose signature no longer matches its content. `make_app_bundle.sh` now re-signs ad-hoc after that step.
- Status-bar icon and badge upgraded from a raw emoji glyph to a proper template SF Symbol (`note.text`); the badge is now a solid accent-color disc with a subtle border/shadow; the note card is now a rounded, bordered panel with a small labeled header and padded text, instead of a bare full-bleed text view.
- **Menu-bar status item doesn't render in this environment**, confirmed with a minimal standalone test app unrelated to Flipside's own code (a bright red "TEST123" badge was also invisible, both via the assistant's own launches and the user's). Root cause not identified (likely an environment/macOS-version-specific restriction on Control-Center-hosted status items from ad-hoc-signed processes). Rather than depend on it, switched to `.regular` activation policy (Dock icon) with a real `MainWindowController` shown on launch — confirmed visible. The status item is left in the code in case the underlying issue is environment-specific and resolves later; it's not the primary way to interact with the app for now.
- **Crash on quit / after tracked windows closed**: `BadgeWindowController`, `CardWindowController`, `MainWindowController`, and `OrphanedNotesWindowController` each hold their own strong reference to an `NSWindow`, but `NSWindow.isReleasedWhenClosed` defaults to `true` — AppKit frees the window the moment `.close()` runs, so the Swift object's own later release of it is a double-release, corrupting memory (surfaced later, in this case as a `SIGSEGV` in `objc_release` during `NSApplication.run()`'s autorelease pool drain at quit — caught from a real crash report the user provided). Fixed by setting `isReleasedWhenClosed = false` in all four.
- **Badges never appeared, even once window enumeration worked (12-13 windows tracked correctly)**: `kAXPositionAttribute`/`kAXSizeAttribute` report frames in AX's "global display coordinates" (origin top-left, Y down), but `NSWindow.setFrameOrigin`/`.setFrame` expect Cocoa's screen coordinates (origin bottom-left, Y up). Both `AXWindowReader` (initial enumeration) and `WindowTracker`'s move/resize handler fed raw, unconverted AX rects into `TrackedWindow`, which `BadgeWindowController` then fed straight into `NSWindow` — every badge landed at the vertically mirrored wrong spot on screen, nowhere near the tracked window's actual corner. Isolated by first confirming (with a standalone test) that borderless/floating windows do render correctly in this environment, ruling out another environment-level rendering restriction before looking at the app's own coordinate math. Fixed with `AXWindowReader.convertAXRectToCocoa(origin:size:)`, applied at both read sites; added `AXWindowReaderTests` as a regression test.
- Added `scripts/uninstall.sh` (stops Flipside, removes the old `.app`, resets the Accessibility TCC grant for `com.flipside.app`) — every ad-hoc re-sign leaves stale, ambiguous "Flipside" entries in System Settings > Privacy & Security > Accessibility. Initially wired into `make_app_bundle.sh`, then **deliberately un-wired**: resetting permission on every rebuild forced a manual re-grant after each build, which made iterating unusable. It is now an explicit, separate action; the build script only stops the running process.

### Fixes from live end-to-end testing (second round)

- **Typing in the note card did nothing.** `NSWindow.canBecomeKey` returns `false` for `.borderless` windows, and a non-key window never receives key events — the card showed a caret but swallowed every keystroke. Added a `KeyableWindow` subclass overriding `canBecomeKey`/`canBecomeMain`, and `show()` now uses `makeKeyAndOrderFront` + `NSApp.activate` (the target app is frontmost when the badge is clicked).
- **The flipped card was a dead end.** It spans the tracked window's full frame, which includes the corner the badge occupies — so it covered the control that opened it, with no way back. Added a Done button and Escape handling on the card, and the badge is re-ordered above the card after a flip.
- **The flip settled mirrored.** A continuous 0°→180° rotation shows the back face reversed (`CALayer.isDoubleSided` defaults to `true`), so note text rendered backwards and read as "broken/not visible". Replaced with a two-stage out-to-90°/back-to-identity flip, content swapped at the edge-on midpoint.
- **The flip visibly stuttered.** `syncOverlays()` re-set *every* tracked window's frame on *any* window's move/resize event anywhere on the system; with a busy chat app running this fired constantly and reset the flipping card's frame mid-animation. Frame updates are now skipped when unchanged.
- **Badges only appeared after clicking Flip, never on launch.** Initial badge visibility went through `setMinimized()`, whose no-change guard short-circuits when the value matches — which it always does for a non-minimized window. Visibility now has a single owner (`updateVisibility()`, driven by `hasUsableFrame && !isMinimized`) called at overlay creation.
- **The "Flip" button vanished on rows with long window titles.** No Auto Layout content priorities were set, so the label won the layout fight and compressed the button to a sliver. Label now truncates; button holds its intrinsic width.
- **Notes appeared lost after quitting an app — they weren't.** Confirmed by querying the encrypted DB directly: the note was intact under `com.hnc.Discord::title::@Julie - Discord`, while an empty note sat under the title shown in the UI. Cause: identity resolved once at overlay creation and never updated, so notes for retitling apps drifted onto stale keys. Now follows the live window via `kAXTitleChangedNotification` (spec §7.2).
- **Relaunched apps weren't picked up.** `didLaunchApplicationNotification` fires before an app has created any windows, and `kAXWindowCreatedNotification` was never subscribed to — so the window appearing moments later went unnoticed. Added it, plus a 3s rescan safety net (spec §6.2.2).
- **Empty-note garbage.** Every window seen got a DB row immediately, including a fresh `session::<uuid>` per untitled window per scan — 13 of the user's 39 stored notes were empty session rows. Notes are now written on first edit (spec §7.3).
- **Chrome per-profile notes were dead code.** The profile qualifier was only applied on the Tier 2 path, but Chrome resolves to Tier 1 via the tab URL — so it could never take effect for the one browser it existed for, and two profiles on the same URL would have shared a note (the exact collision spec Story 1 exists to prevent). The qualifier now scopes whichever tier applies (spec §7.1.1).


## Known gaps and unverified areas

- **Signing & notarization (Task 25)** — scripted, never executed; needs an Apple Developer ID certificate. This is upstream of several other problems: ad-hoc signing is why permission grants keep resetting, why Gatekeeper flags the app, and possibly why the menu-bar status item never renders (spec §16).
- **Menu-bar status item doesn't render** in this environment (spec §16.1) — isolated to the environment, not this codebase, via a minimal standalone test app. Root cause unknown. The Dock icon + main window is the working entry point.
- **Chrome per-profile notes** — unit tested, never run against a live second Chrome profile (only the Default profile exists on this machine, and Default omits `--profile-directory` entirely).
- **Multi-display** — single-display machine; per-screen clamping and coordinate conversion are implemented but unexercised.
- **Full-screen / Spaces behaviour** — now explicitly handled (spec §8.5: `.fullScreenAuxiliary`, active-Space filtering via CGWindowList, Space-change notifications), unit tested, but **never confirmed against a live full-screen app**.
- **Multi-window stress test (Task 23)** — not performed.
- **VS Code** — tier and unsaved-indicator (`●`) title stripping implemented and unit tested, never observed against the real app.
- **Manual promotion of an orphaned (Tier-3) note** to a stable key — spec §7 allows for it; not implemented, the orphaned list is read-only.
- **Ambiguous-match confirmation UI (Task 19)** — implemented, never triggered in live use.
