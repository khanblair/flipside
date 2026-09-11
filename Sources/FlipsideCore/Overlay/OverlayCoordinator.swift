@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

@MainActor
private final class WindowOverlay {
    let badge = BadgeWindowController()
    let card = CardWindowController()
    let stateMachine = FlipStateMachine()

    init(trackedWindow: TrackedWindow, noteStore: InMemoryNoteStore, onBadgeClicked: @escaping () -> Void) {
        badge.onBadgeClicked = onBadgeClicked
        card.setFrame(trackedWindow.frame)
        badge.reposition(toCornerOf: trackedWindow.frame)
        badge.show()
        card.textView.string = noteStore.body(for: ObjectIdentifier(card))
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
/// positioned on move/resize, and drives the card-flip animation (spec §8)
/// on badge click. Notes are in-memory only at this stage (Phase 2) — no
/// persistence yet (that's Task 18).
@MainActor
public final class OverlayCoordinator {
    private let tracker: WindowTracker
    private let noteStore: InMemoryNoteStore
    private var overlaysByWindow: [AXUIElement: WindowOverlay] = [:]
    private let flipDuration: CFTimeInterval = 0.35
    private let perspectiveDistance: CGFloat = 1000

    public init(tracker: WindowTracker, noteStore: InMemoryNoteStore = InMemoryNoteStore()) {
        self.tracker = tracker
        self.noteStore = noteStore
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
                let overlay = WindowOverlay(trackedWindow: window, noteStore: noteStore) { [weak self] in
                    self?.toggleFlip(for: element)
                }
                overlaysByWindow[element] = overlay
            }
        }

        let goneKeys = overlaysByWindow.keys.filter { !seen.contains($0) }
        for key in goneKeys {
            guard let overlay = overlaysByWindow.removeValue(forKey: key) else { continue }
            noteStore.setBody(overlay.card.textView.string, for: ObjectIdentifier(overlay.card))
            overlay.teardown()
        }
    }

    private func toggleFlip(for element: AXUIElement) {
        guard let overlay = overlaysByWindow[element] else { return }
        let newState = overlay.stateMachine.toggle()

        switch newState {
        case .back:
            overlay.card.textView.string = noteStore.body(for: ObjectIdentifier(overlay.card))
            overlay.card.show()
            animateFlip(overlay.card.window, from: 0, to: 180, completion: nil)
        case .front:
            noteStore.setBody(overlay.card.textView.string, for: ObjectIdentifier(overlay.card))
            animateFlip(overlay.card.window, from: 180, to: 0) { [weak overlay] in
                overlay?.card.hide()
            }
        }
    }

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
