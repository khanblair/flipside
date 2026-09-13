import AppKit

/// A small, circular, always-on-top badge pinned to a tracked window's
/// corner (spec §8.1). Styled as a solid accent-colored disc with a
/// centered SF Symbol, matching the system's own menu-bar/notification
/// badge language rather than a raw emoji glyph.
@MainActor
public final class BadgeWindowController {
    private let window: NSWindow
    public var onBadgeClicked: (() -> Void)?

    private static let diameter: CGFloat = 26
    private static let cornerInset: CGFloat = 6

    public init() {
        let diameter = Self.diameter
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Default is true, which frees the window the moment .close() is
        // called — but this controller also holds its own strong reference,
        // so that default causes a double-release once this controller is
        // itself deallocated. False makes this controller the sole owner.
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        // .fullScreenAuxiliary lets this sit over a full-screened app, which
        // lives in its own Space. Deliberately NOT .canJoinAllSpaces: that
        // shows the overlay on every Space, so a window on the desktop Space
        // would have its badge bleeding over an unrelated full-screen Space.
        // Which Space it belongs on is decided per-sync via ActiveSpaceFilter.
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let button = NSButton(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        button.title = ""
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = diameter / 2
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        button.layer?.borderWidth = 0.5
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.35
        button.layer?.shadowRadius = 3
        button.layer?.shadowOffset = CGSize(width: 0, height: -1)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Flip note")?
            .withSymbolConfiguration(symbolConfig)
        button.contentTintColor = .white
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        button.target = self
        button.action = #selector(handleClick)
        window.contentView = button
    }

    public func reposition(toCornerOf targetFrame: CGRect) {
        let diameter = Self.diameter
        let badgeOrigin = CGPoint(
            x: targetFrame.maxX - diameter - Self.cornerInset,
            y: targetFrame.maxY - diameter - Self.cornerInset
        )
        window.setFrameOrigin(badgeOrigin)
    }

    public func show() { window.orderFront(nil) }
    public func hide() { window.orderOut(nil) }
    public func close() { window.close() }

    @objc private func handleClick() {
        onBadgeClicked?()
    }
}
