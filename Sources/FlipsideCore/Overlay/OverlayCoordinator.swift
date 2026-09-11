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

    init(trackedWindow: TrackedWindow, note: Note) {
        self.note = note
        card.setFrame(trackedWindow.frame)
        badge.reposition(toCornerOf: trackedWindow.frame)
        badge.show()
        card.textView.string = note.body
    }

    func updateFrame(_ frame: CGRect) {
        badge.reposition(toCornerOf: frame)
        card.setFrame(frame)
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
            } else {
                let note = resolveOrCreateNote(for: window)
                let overlay = WindowOverlay(trackedWindow: window, note: note)
                overlay.badge.onBadgeClicked = { [weak self] in self?.toggleFlip(for: element) }
                overlaysByWindow[element] = overlay
            }
        }

        for key in overlaysByWindow.keys where !seen.contains(key) {
            guard let overlay = overlaysByWindow.removeValue(forKey: key) else { continue }
            persist(overlay)
            overlay.teardown()
        }
    }

    private func toggleFlip(for element: AXUIElement) {
        guard let overlay = overlaysByWindow[element] else { return }
        let newState = overlay.stateMachine.toggle()

        switch newState {
        case .back:
            overlay.card.textView.string = overlay.note.body
            overlay.card.show()
            animateFlip(overlay.card.window, from: 0, to: 180, completion: nil)
        case .front:
            overlay.note.body = overlay.card.textView.string
            persist(overlay)
            animateFlip(overlay.card.window, from: 180, to: 0) { [weak overlay] in
                overlay?.card.hide()
            }
        }
    }

    // MARK: - Persistence (Task 18)

    private func resolveOrCreateNote(for window: TrackedWindow) -> Note {
        let now = Int64(Date().timeIntervalSince1970)

        guard let repository = noteRepository else {
            return Self.freshNote(for: window, identityKey: UUID().uuidString, tier: .session, now: now)
        }

        guard let resolved = WindowIdentityResolver.resolve(window) else {
            // Tier 3: no stable key. Still persisted (Open Questions §12 item 1:
            // retained, not discarded) under a one-off session key so it can be
            // surfaced later as an orphaned note (Task 20) — but it will never
            // automatically match again on a future launch.
            let note = Self.freshNote(for: window, identityKey: "session::\(UUID().uuidString)", tier: .session, now: now)
            log { try repository.upsert(note) }
            return note
        }

        if let existing = log({ try repository.findNote(identityKey: resolved.key) }) ?? nil {
            return existing
        }

        if resolved.tier == .title,
           let candidates = log({ try repository.notesWithGenericTitle(bundleID: window.bundleID) }),
           case .unambiguous(let note) = AmbiguousMatchDetector.resolve(candidates: candidates) {
            // Exactly one orphaned note with a matching generic title pattern for
            // this bundle: reattach it to this window's concrete key going forward.
            var reattached = note
            reattached.identityKey = resolved.key
            reattached.identityTier = resolved.tier
            log { try repository.upsert(reattached) }
            return reattached
        }
        // Multiple generic-title candidates is genuinely ambiguous — Task 19's
        // confirmation UI (not yet built) owns that decision. Fall through to a
        // fresh note here rather than silently guessing which one is meant.

        let note = Self.freshNote(for: window, identityKey: resolved.key, tier: resolved.tier, now: now)
        log { try repository.upsert(note) }
        return note
    }

    private func persist(_ overlay: WindowOverlay) {
        guard let repository = noteRepository else { return }
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

    private func animateFlip(_ window: NSWindow, from: CGFloat, to: CGFloat, completion: (() -> Void)?) {
        guard let contentView = window.contentView else {
            completion?()
            return
        }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            completion?()
            return
        }

        let fromTransform = FlipTransform.transform(angleDegrees: from, perspectiveDistance: perspectiveDistance)
        let toTransform = FlipTransform.transform(angleDegrees: to, perspectiveDistance: perspectiveDistance)

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: fromTransform)
        animation.toValue = NSValue(caTransform3D: toTransform)
        animation.duration = flipDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.transform = toTransform
        layer.add(animation, forKey: "flip")
        CATransaction.commit()
    }
}
