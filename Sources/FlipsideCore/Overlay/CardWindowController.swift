import AppKit

@MainActor
public final class CardWindowController {
    public let window: NSWindow
    public let textView: NSTextView

    public init() {
        window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(origin: .zero, size: window.frame.size)
        scrollView.autoresizingMask = [.width, .height]

        let textView = scrollView.documentView as! NSTextView
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        self.textView = textView

        window.contentView = scrollView
    }

    public func setFrame(_ frame: CGRect) {
        window.setFrame(frame, display: true)
    }

    public func show() { window.orderFront(nil) }
    public func hide() { window.orderOut(nil) }
    public func close() { window.close() }
}
