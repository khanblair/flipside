import AppKit

/// The note card shown after a flip (spec §8.1), styled like a Google Keep
/// note: a paper-like surface, a header naming the window the note belongs
/// to, generous padding, placeholder text while empty, and an explicit
/// "Done" affordance.
///
/// That last part matters for more than polish: the card is sized to the
/// tracked window's full frame, which means it covers the corner badge that
/// triggered it. Without a dismiss control on the card itself, a flipped
/// window is a dead end — you can't reach the badge to flip back.
@MainActor
public final class CardWindowController: NSObject, NSTextViewDelegate {
    public let window: NSWindow
    public let textView: NSTextView

    private let headerLabel = NSTextField(labelWithString: "Note")
    private let placeholderLabel = NSTextField(labelWithString: "Take a note…")

    /// Invoked when the user dismisses the card from the card itself (its
    /// Done button or the Escape key) rather than from the badge.
    public var onClose: (() -> Void)?

    public override init() {
        // KeyableWindow, not NSWindow: a plain borderless window can't become
        // key, and a non-key window never receives keystrokes — the note card
        // would look focused but ignore all typing.
        window = KeyableWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView

        super.init()

        // See BadgeWindowController: this controller holds its own strong
        // reference to `window`, so the default (true) causes a double
        // release once .close() has already freed it once.
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window.contentView = buildContainer(scrollView: scrollView)
    }

    private func buildContainer(scrollView: NSScrollView) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        // A note surface rather than a generic window background: this is
        // the colour used for editable text areas, so it reads as paper in
        // light mode and a legible dark card in dark mode.
        containerView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.separatorColor.cgColor

        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(iconView)
        header.addSubview(headerLabel)
        header.addSubview(doneButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.drawsBackground = false
        textView.delegate = self
        textView.allowsUndo = true

        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(header)
        containerView.addSubview(scrollView)
        containerView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            headerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            headerLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -12),

            doneButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            header.topAnchor.constraint(equalTo: containerView.topAnchor),
            header.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 23)
        ])

        return containerView
    }

    /// Names the window this note is attached to, so a flipped card isn't
    /// an anonymous panel floating over the screen.
    public func setTitle(_ title: String) {
        headerLabel.stringValue = title
    }

    public func setBody(_ body: String) {
        textView.string = body
        updatePlaceholderVisibility()
    }

    public func setFrame(_ frame: CGRect) {
        window.setFrame(frame, display: true)
    }

    public func show() {
        // makeKeyAndOrderFront (not just orderFront) plus activating the app:
        // both are needed for the card to actually receive typing, since the
        // target app is frontmost at the moment the badge is clicked.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        updatePlaceholderVisibility()
    }

    public func hide() { window.orderOut(nil) }
    public func close() { window.close() }

    public func textDidChange(_ notification: Notification) {
        updatePlaceholderVisibility()
    }

    /// Escape flips the card back, matching the Done button — the card
    /// covers the badge, so it must be dismissible from itself.
    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    @objc private func doneClicked() {
        onClose?()
    }
}
