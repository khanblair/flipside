# Flipside — Changelog / Implementation Checklist

Tracks implementation status against [flipside-spec.md](flipside-spec.md). **Current status: 42/42 unit tests passing** (`swift test`), full package + `.app` bundle assembly build clean. Each item is marked:

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

## Phase 1 — Core Mechanism

- [x] Task 1 — Project scaffolding (menu-bar app shell, `Info.plist`, no-sandbox entitlements) — `swift build` passes
- [~] Task 2 — Accessibility permission flow — implemented and compiles; the actual OS permission prompt needs an interactive GUI session to verify
- [x] Task 3 — `TrackedWindow` + `WindowRegistry` (pure logic, unit tested) — 7/7 tests passing
- [x] Task 4 — `AXWindowReader` + `WindowTracker` live enumeration — **live-verified on the user's machine**: 13 real windows correctly enumerated across Finder, Chrome, Discord, Docker Desktop, WhatsApp, System Settings, and Notification Center, once Accessibility permission was actually granted for the current build
- [~] Task 5 — AXObserver + NSWorkspace live notifications (move/resize/destroy/miniaturize, launch/terminate) — implemented, compiles; initial enumeration confirmed live, move/resize/close notification behavior still needs live verification
- [~] Task 6 — Badge overlay window (corner-pinned, repositions, tears down on close) — implemented, compiles; was blocked by both a crash and a coordinate-space bug (see Post-review fixes), both now fixed — not yet visually confirmed by the user
- [ ] Task 7 — Accessibility Inspector audit across target apps (investigation, produces findings table) — not started, needs a human at the machine

## Phase 2 — Flip + Notes

- [~] Task 8 — Card overlay window (full-size, matches tracked frame) — implemented, compiles; needs live verification
- [x] Task 9 — `FlipTransform` — pure `CATransform3D` math (unit tested) — 3/3 tests passing
- [x] Task 10 — `FlipStateMachine` — pure front/back state (unit tested) — 2/2 tests passing
- [~] Task 11 — Wire badge click → flip → card show/hide; in-memory note store — `OverlayCoordinator` implemented and wired into `main.swift`, compiles; the actual animation/click flow needs a live GUI session to verify

## Phase 3 — Persistence

- [x] Task 12 — SQLCipher-backed `Database` wrapper + schema (unit tested: wrong key cannot read the file) — 2/2 tests passing
- [x] Task 13 — `KeychainKeyStore` (unit tested: round-trip, idempotent create) — 3/3 tests passing
- [x] Task 14 — `Note` model + `NoteRepository` (unit tested: upsert/find, conflict resolution) — 4/4 tests passing
- [x] Task 15 — `IdentityKeyBuilder` — Tier 1/2/3 (unit tested, incl. VS Code title normalization) — 10/10 tests passing
- [x] Task 16 — `ChromeProfileResolver` — `--profile-directory` extraction (unit tested pure core; syscall parsing additionally verified empirically against live Chrome PIDs on this machine) — 3/3 tests passing. **Finding:** default-profile Chrome windows carry no `--profile-directory` flag at all — `profileDirectory(forPID:)` returns `nil` for them; downstream identity-key logic must treat `nil` as "no profile suffix, use plain Tier 2," not as an error.
- [x] Task 17 — `AmbiguousMatchDetector` (unit tested, all three outcomes) — 3/3 tests passing
- [x] Task 18 — Wire persistence into the overlay coordinator — `WindowIdentityResolver` + `NoteRepository.notesWithGenericTitle` (candidate query for the ambiguous-match rule) + `OverlayCoordinator` load/save/reattach + `main.swift` opens the real encrypted DB at launch. Reattachment auto-applies only when exactly one generic-title candidate exists; genuinely ambiguous cases fall through to a fresh note pending Task 19. Compiles and passes the full suite; live reattachment behavior needs a GUI session to verify.

## Phase 4 — Polish

- [~] Task 19 — Ambiguous-match confirmation UI — `AmbiguousMatchPrompt` (modal `NSAlert`) wired into `OverlayCoordinator`'s `.ambiguous` case; compiles, not unit-testable (no way to drive a real modal loop headlessly), needs a live GUI session to verify
- [~] Task 20 — Orphaned / Tier 3 notes list — `NoteRepository.allNotes(tier:)` is unit tested (1/1 passing); `OrphanedNotesWindowController` + status-bar menu item compile, needs a live GUI session to verify. Read-only for v1 — manual promotion to a Tier-2 key (spec §7's "the user can manually promote it") is not implemented.
- [x] Task 21 — `Debouncer` utility, wired into `WindowTracker`'s move/resize AX callbacks (destroy notifications stay immediate) — 2/2 unit tests passing
- [~] Task 22 — Minimized-window badge hide/restore — `TrackedWindow.isMinimized` + `WindowRegistry.updateMinimized` unit tested (2/2 passing); `WindowTracker`/`OverlayCoordinator` wiring compiles, needs a live GUI session to verify actual minimize/restore behavior
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

## Known gaps requiring the user / a live macOS GUI session

- Accessibility permission grant (Task 2) is an interactive OS prompt — cannot be clicked through non-interactively.
- Live AX tracking, badge/card rendering, flip animation, and the ambiguous-match/orphaned-notes UI (Tasks 4–11, 18–22) are written and compile, but genuinely exercising them requires running the built app (`open build/Flipside.app` after `scripts/make_app_bundle.sh`) with Accessibility access granted.
- Task 7 (Accessibility Inspector audit) and Task 23 (multi-window stress test) are investigation tasks with no code to write — they need a human at the machine.
- Notarization (Task 25) requires an Apple Developer ID certificate and notarization credentials not available in this environment — the script is written but not executed.
- Manual promotion of an orphaned (Tier-3) note to a stable Tier-2 key, mentioned in spec §7 as something "the user can manually promote," is not implemented — the orphaned-notes list (Task 20) is read-only in this pass.
