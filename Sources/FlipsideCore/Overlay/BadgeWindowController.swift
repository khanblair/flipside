import AppKit

@MainActor
public final class BadgeWindowController {
    private let window: NSWindow
    public var onBadgeClicked: (() -> Void)?

    public init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .circular
        button.title = "🗂"
        button.target = self
        button.action = #selector(handleClick)
        window.contentView = button
    }

    public func reposition(toCornerOf targetFrame: CGRect) {
        let badgeOrigin = CGPoint(x: targetFrame.maxX - 28, y: targetFrame.maxY - 28)
        window.setFrameOrigin(badgeOrigin)
    }

    public func show() { window.orderFront(nil) }
    public func hide() { window.orderOut(nil) }
    public func close() { window.close() }

    @objc private func handleClick() {
        onBadgeClicked?()
    }
}
