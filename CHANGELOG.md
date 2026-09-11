# Flipside — Changelog / Implementation Checklist

Tracks implementation status against [flipside-spec.md](flipside-spec.md). Each item is marked:

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
- [~] Task 4 — `AXWindowReader` + `WindowTracker` live enumeration — implemented, compiles; reading real AX attributes needs a live GUI session to verify (not unit-testable — no fake `AXUIElement`)
- [~] Task 5 — AXObserver + NSWorkspace live notifications (move/resize/destroy/miniaturize, launch/terminate) — implemented, compiles; needs live verification
- [~] Task 6 — Badge overlay window (corner-pinned, repositions, tears down on close) — implemented, compiles; visual behavior needs live verification
- [ ] Task 7 — Accessibility Inspector audit across target apps (investigation, produces findings table) — not started, needs a human at the machine

## Phase 2 — Flip + Notes

- [~] Task 8 — Card overlay window (full-size, matches tracked frame) — implemented, compiles; needs live verification
- [x] Task 9 — `FlipTransform` — pure `CATransform3D` math (unit tested) — 3/3 tests passing
- [x] Task 10 — `FlipStateMachine` — pure front/back state (unit tested) — 2/2 tests passing
- [~] Task 11 — Wire badge click → flip → card show/hide; in-memory note store — `OverlayCoordinator` implemented and wired into `main.swift`, compiles; the actual animation/click flow needs a live GUI session to verify

## Phase 3 — Persistence

- [ ] Task 12 — SQLCipher-backed `Database` wrapper + schema (unit tested: wrong key cannot read the file) — in progress
- [x] Task 13 — `KeychainKeyStore` (unit tested: round-trip, idempotent create) — 3/3 tests passing
- [ ] Task 14 — `Note` model + `NoteRepository` (unit tested: upsert/find, conflict resolution) — in progress
- [x] Task 15 — `IdentityKeyBuilder` — Tier 1/2/3 (unit tested, incl. VS Code title normalization) — 10/10 tests passing
- [x] Task 16 — `ChromeProfileResolver` — `--profile-directory` extraction (unit tested pure core; syscall parsing additionally verified empirically against live Chrome PIDs on this machine) — 3/3 tests passing. **Finding:** default-profile Chrome windows carry no `--profile-directory` flag at all — `profileDirectory(forPID:)` returns `nil` for them; downstream identity-key logic must treat `nil` as "no profile suffix, use plain Tier 2," not as an error.
- [x] Task 17 — `AmbiguousMatchDetector` (unit tested, all three outcomes) — 3/3 tests passing
- [ ] Task 18 — Wire persistence into the overlay coordinator (load/save/match on reappearance) — blocked on Task 12/14

## Phase 4 — Polish

- [ ] Task 19 — Ambiguous-match confirmation UI
- [ ] Task 20 — Orphaned / Tier 3 notes list
- [x] Task 21 — `Debouncer` utility (unit tested) — 2/2 tests passing; not yet wired into `WindowTracker`'s AXObserver callbacks
- [ ] Task 22 — Minimized-window badge hide/restore
- [ ] Task 23 — Multi-window stress test pass (investigation)

## Phase 5 — Packaging

- [~] Task 24 — Signing & entitlements audit — `scripts/make_app_bundle.sh` verified: assembles a real self-contained `.app` (bundled `libsqlcipher.dylib`, `@rpath` rewritten and confirmed via `otool -L`/`otool -l`), entitlements file has no sandbox key; actual `codesign` with a Developer ID identity needs credentials not available here
- [~] Task 25 — Notarization script — written (`scripts/notarize.sh`), not executed; requires the user's own Apple Developer ID certificate + notarytool credentials
- [x] Task 26 — DMG build script — `scripts/build_dmg.sh` run end-to-end against a built bundle; `hdiutil verify` passed

## Known gaps requiring the user / a live macOS GUI session

- Accessibility permission grant (Task 2) is an interactive OS prompt — cannot be clicked through non-interactively.
- Live AX tracking, badge/card rendering, and flip animation (Tasks 4–11, 18–22) can be written and compiled, but genuinely exercising them requires running the built app with Accessibility access granted.
- Notarization (Task 25) requires an Apple Developer ID certificate and notarization credentials not available in this environment — the script will be written but not executed.
