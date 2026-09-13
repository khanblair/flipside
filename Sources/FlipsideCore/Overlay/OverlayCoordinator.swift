@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import QuartzCore
import Foundation

@MainActor
private final class WindowOverlay {
    let badge = BadgeWindowController()
    let card = CardWindowController()
    let stateMachine = FlipStateMachine()
    var note: Note
    private(set) var isMinimized = false
    private var lastFrame: CGRect

    private let debugName: String

    init(trackedWindow: TrackedWindow, note: Note) {
        self.note = note
        self.lastFrame = trackedWindow.frame
        self.debugName = Self.cardTitle(for: trackedWindow)
        applyFrame(trackedWindow.frame)
        card.setTitle(debugName)
        card.setBody(note.body)
        setMinimized(trackedWindow.isMinimized)
    }

    static func cardTitle(for window: TrackedWindow) -> String {
        guard let title = window.title, !title.isEmpty else { return window.appName }
        return "\(window.appName) — \(title)"
    }

    private func applyFrame(_ frame: CGRect) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let usableFrame = CardFrameSanitizer.sanitized(frame, visibleScreenFrames: screens) else {
            // Degenerate or offscreen window (AX reports plenty of these):
            // nothing sensible to attach an overlay to. Logged so it's
            // visible why a given window never gets a badge.
            NSLog("Flipside: no overlay for '%@' — unusable frame %@", debugName, NSStringFromRect(frame))
            badge.hide()
            card.hide()
            return
        }
        NSLog("Flipside: overlay for '%@' at %@", debugName, NSStringFromRect(usableFrame))
        card.setFrame(usableFrame)
        badge.reposition(toCornerOf: usableFrame)
    }

    /// No-ops when the frame hasn't actually changed. `syncOverlays()` calls
    /// this for every tracked window on any AX move/resize notification
    /// *anywhere* on the system, not just the window that actually moved —
    /// with several windows tracked, that's frequent. Without this guard,
    /// a busy, unrelated window (e.g. a chat app's UI updates) would keep
    /// re-setting this card's `NSWindow` frame, visibly interrupting a
    /// flip animation in progress on it.
    func updateFrame(_ frame: CGRect) {
        guard frame != lastFrame else { return }
        lastFrame = frame
        applyFrame(frame)
    }

    /// Open Questions §12 item 2 (Task 22): minimized windows hide their
    /// badge rather than shrinking into the Dock region. The card, if it
    /// happened to be showing, also hides — it only reappears via an
    /// explicit flip once the window is restored, never automatically.
    func setMinimized(_ minimized: Bool) {
        guard minimized != isMinimized else { return }
        isMinimized = minimized
        if minimized {
            badge.hide()
            card.hide()
        } else {
            badge.show()
        }
    }

    func teardown() {
        badge.close()
        card.close()
    }
}

/// Wires `WindowTracker` to per-window badge/card overlay pairs: creates
/// and tears down overlays as tracked windows appear/disappear, keeps them
/// positioned on move/resize, drives the card-flip animation (spec §8) on
/// badge click, and persists note bodies through `NoteRepository` keyed by
/// the window's identity (spec §7, Task 18). Pass `noteRepository: nil` to
/// run without persistence (e.g. in a context where the encrypted database
/// couldn't be opened) — notes then live only in memory for the session.
@MainActor
public final class OverlayCoordinator {
    private let tracker: WindowTracker
    private let noteRepository: NoteRepository?
    private var overlaysByWindow: [AXUIElement: WindowOverlay] = [:]
    private let flipDuration: CFTimeInterval = 0.35
    private let perspectiveDistance: CGFloat = 1000

    public init(tracker: WindowTracker, noteRepository: NoteRepository? = nil) {
        self.tracker = tracker
        self.noteRepository = noteRepository
        tracker.onWindowsChanged = { [weak self] in self?.syncOverlays() }
    }

    public func start() {
        tracker.start()
        syncOverlays()
    }

    private func syncOverlays() {
        let keyed = tracker.currentWindowsKeyed()
        var seen = Set<AXUIElement>()

        for (element, window) in keyed {
            seen.insert(element)
            if let overlay = overlaysByWindow[element] {
                overlay.updateFrame(window.frame)
                overlay.setMinimized(window.isMinimized)
                followIdentityChange(overlay, for: window)
            } else {
                let note = resolveOrCreateNote(for: window)
                let overlay = WindowOverlay(trackedWindow: window, note: note)
                overlay.badge.onBadgeClicked = { [weak self] in self?.toggleFlip(for: element) }
                // The card covers the whole tracked window, badge included,
                // so it must also be dismissible from itself.
                overlay.card.onClose = { [weak self] in self?.flipBackIfNeeded(for: element) }
                overlaysByWindow[element] = overlay
            }
        }

        for key in overlaysByWindow.keys where !seen.contains(key) {
            guard let overlay = overlaysByWindow.removeValue(forKey: key) else { continue }
            persist(overlay)
            overlay.teardown()
        }
    }

    /// Triggers the same flip a badge click would, for the tracked window
    /// identified by `element` (from `WindowTracker.currentWindowsKeyed()`).
    /// Exposed so a fallback UI (e.g. a "Flip" button in the main window's
    /// tracked-windows list) can drive the flip when the corner badge isn't
    /// a reliable trigger to click.
    public func toggleFlip(for element: AXUIElement) {
        guard let overlay = overlaysByWindow[element], !overlay.isMinimized else { return }
        let newState = overlay.stateMachine.toggle()

        switch newState {
        case .back:
            overlay.card.show()
            animateFlip(overlay.card.window, swapContent: {
                overlay.card.setBody(overlay.note.body)
            }, completion: {
                // Keep the badge above the card: the card spans the whole
                // tracked window, so without this the badge that triggered
                // the flip ends up buried underneath it.
                overlay.badge.show()
            })
        case .front:
            animateFlip(overlay.card.window, swapContent: { [weak self] in
                overlay.note.body = overlay.card.textView.string
                self?.persist(overlay)
            }, completion: { [weak overlay] in
                overlay?.card.hide()
            })
        }
    }

    /// Flips a card back to the front if it's currently showing. Used by the
    /// card's own Done button / Escape key, which must not toggle a card
    /// that's already front-facing.
    private func flipBackIfNeeded(for element: AXUIElement) {
        guard let overlay = overlaysByWindow[element], overlay.stateMachine.state == .back else { return }
        toggleFlip(for: element)
    }

    // MARK: - Identity drift

    /// Keeps a live window's note attached as its title changes.
    ///
    /// The identity key used to be resolved once, at overlay creation, and
    /// never revisited — so for any app whose title changes over the window's
    /// life (a chat app switching channels, a browser switching tabs) the note
    /// drifted out of sync: edits were written under a stale key, and on the
    /// next launch the window's *current* title produced a different key with
    /// no match, so the note looked lost. It wasn't — it was filed under the
    /// old title. This follows the window instead.
    private func followIdentityChange(_ overlay: WindowOverlay, for window: TrackedWindow) {
        guard let resolved = WindowIdentityResolver.resolve(window) else { return }
        guard resolved.key != overlay.note.identityKey else { return }

        let existing = log { try noteRepository?.findNote(identityKey: resolved.key) } ?? nil

        switch (overlay.note.body.isEmpty, existing) {
        case (true, .some(let stored)):
            // We're carrying nothing and the new identity already has a note:
            // adopt it, so returning to a previously-noted title brings its
            // note back rather than showing a blank card over it.
            overlay.note = stored
            overlay.card.setBody(stored.body)
        case (false, .some(let stored)) where !stored.body.isEmpty:
            // Both sides have content. Re-keying would overwrite the stored
            // note (identity_key is UNIQUE), so keep ours where it is rather
            // than destroying someone else's note.
            return
        default:
            // Safe to follow: either nothing is stored under the new key, or
            // what's there is empty.
            overlay.note.identityKey = resolved.key
            overlay.note.identityTier = resolved.tier
        }

        overlay.note.lastTitle = window.title
        overlay.note.lastDocPath = window.documentPath
        overlay.card.setTitle(WindowOverlay.cardTitle(for: window))
        persist(overlay)
    }

    // MARK: - Persistence (Task 18)

    private func resolveOrCreateNote(for window: TrackedWindow) -> Note {
        let now = Int64(Date().timeIntervalSince1970)

        guard let repository = noteRepository else {
            return Self.freshNote(for: window, identityKey: UUID().uuidString, tier: .session, now: now)
        }

        guard let resolved = WindowIdentityResolver.resolve(window) else {
            // Tier 3: no stable key. Kept in memory now and only written once
            // it has content (Open Questions §12 item 1: retained, not
            // discarded) — it will never automatically match again on a
            // future launch, but an empty one isn't worth a row.
            return Self.freshNote(for: window, identityKey: "session::\(UUID().uuidString)", tier: .session, now: now)
        }

        if let existing = log({ try repository.findNote(identityKey: resolved.key) }) ?? nil {
            return existing
        }

        if resolved.tier == .title,
           let candidates = log({ try repository.notesWithGenericTitle(bundleID: window.bundleID) }) {
            var reattachTarget: Note?
            switch AmbiguousMatchDetector.resolve(candidates: candidates) {
            case .none:
                break
            case .unambiguous(let note):
                // Exactly one orphaned note with a matching generic title
                // pattern for this bundle: reattach it automatically.
                reattachTarget = note
            case .ambiguous(let ambiguousCandidates):
                // Genuinely ambiguous — per spec §7, don't silently guess;
                // ask the user which one (if any) belongs to this window.
                reattachTarget = AmbiguousMatchPrompt.choose(
                    candidates: ambiguousCandidates,
                    windowTitle: window.title ?? window.appName
                )
            }
            if var reattached = reattachTarget {
                reattached.identityKey = resolved.key
                reattached.identityTier = resolved.tier
                log { try repository.upsert(reattached) }
                return reattached
            }
        }

        // Written on first edit, not on sight — see persist(_:).
        return Self.freshNote(for: window, identityKey: resolved.key, tier: resolved.tier, now: now)
    }

    /// Writes the note only once it actually has content. Every window ever
    /// seen used to get a row immediately on creation, including a freshly
    /// minted `session::<uuid>` row for each untitled window on every scan —
    /// which piled up dozens of empty rows and made the orphaned-notes list
    /// meaningless. An empty note has nothing worth storing.
    private func persist(_ overlay: WindowOverlay) {
        guard let repository = noteRepository else { return }
        guard !overlay.note.body.isEmpty else { return }
        overlay.note.updatedAt = Int64(Date().timeIntervalSince1970)
        log { try repository.upsert(overlay.note) }
    }

    private static func freshNote(for window: TrackedWindow, identityKey: String, tier: IdentityTier, now: Int64) -> Note {
        Note(
            id: UUID().uuidString,
            identityKey: identityKey,
            identityTier: tier,
            body: "",
            createdAt: now,
            updatedAt: now,
            bundleID: window.bundleID,
            appName: window.appName,
            lastTitle: window.title,
            lastDocPath: window.documentPath
        )
    }

    @discardableResult
    private func log<T>(_ operation: () throws -> T) -> T? {
        do {
            return try operation()
        } catch {
            FileHandle.standardError.write(Data("Flipside: note repository error: \(error)\n".utf8))
            return nil
        }
    }

    // MARK: - Flip animation (spec §8.2)

    /// Rotates the card's content away to edge-on (90°, momentarily
    /// invisible — a real physical card looks the same from directly
    /// side-on regardless of which face you started from), calls
    /// `swapContent` at that exact midpoint, then rotates back to identity
    /// (0°, facing the viewer normally).
    ///
    /// A naive single continuous rotation from 0° to 180° would settle with
    /// the card facing the viewer *mirrored* (`CALayer.isDoubleSided`
    /// defaults to `true`, so the back face renders reversed rather than
    /// being culled) — unreadable, and easy to mistake for the card not
    /// rendering at all. Going out to 90° and back to identity instead
    /// means the settled state is always right-side-up, whichever
    /// direction triggered it.
    private func animateFlip(_ window: NSWindow, swapContent: @escaping () -> Void, completion: (() -> Void)?) {
        guard let contentView = window.contentView else {
            swapContent()
            completion?()
            return
        }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            swapContent()
            completion?()
            return
        }

        let halfDuration = flipDuration / 2
        let edgeOnTransform = FlipTransform.transform(angleDegrees: 90, perspectiveDistance: perspectiveDistance)
        let identityTransform = CATransform3DIdentity

        let outAnimation = CABasicAnimation(keyPath: "transform")
        outAnimation.fromValue = NSValue(caTransform3D: identityTransform)
        outAnimation.toValue = NSValue(caTransform3D: edgeOnTransform)
        outAnimation.duration = halfDuration
        outAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            swapContent()
            layer.transform = edgeOnTransform

            let inAnimation = CABasicAnimation(keyPath: "transform")
            inAnimation.fromValue = NSValue(caTransform3D: edgeOnTransform)
            inAnimation.toValue = NSValue(caTransform3D: identityTransform)
            inAnimation.duration = halfDuration
            inAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            layer.transform = identityTransform
            layer.add(inAnimation, forKey: "flipIn")
            CATransaction.commit()
        }
        layer.transform = edgeOnTransform
        layer.add(outAnimation, forKey: "flipOut")
        CATransaction.commit()
    }
}
