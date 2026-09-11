import AppKit

/// The full-size card window shown after a flip (spec §8.1), styled as a
/// rounded, bordered card with a small labeled header — rather than a bare
/// text view — so it reads as a deliberate piece of UI, not a debug window.
/// All colors are dynamic system colors so it adapts to light/dark mode.
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
        // See BadgeWindowController: this controller holds its own strong
        // reference to `window`, so the default (true) causes a double
        // release once .close() has already freed it once.
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.separatorColor.cgColor

        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = NSTextField(labelWithString: "Flipside Note")
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(iconView)
        header.addSubview(headerLabel)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = scrollView.documentView as! NSTextView
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.drawsBackground = false
        self.textView = textView

        containerView.addSubview(header)
        containerView.addSubview(divider)
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            headerLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            header.topAnchor.constraint(equalTo: containerView.topAnchor),
            header.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        window.contentView = containerView
    }

    public func setFrame(_ frame: CGRect) {
        window.setFrame(frame, display: true)
    }

    public func show() { window.orderFront(nil) }
    public func hide() { window.orderOut(nil) }
    public func close() { window.close() }
}
