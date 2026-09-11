import AppKit

/// A visible status/control window shown on launch. Flipside's core feature
/// (badges attached to other apps' windows, per spec §8) doesn't need a
/// window of its own — but this environment's menu-bar status item wasn't
/// rendering reliably, so this gives the user a concrete, always-visible
/// place to confirm the app is alive and see what it's currently tracking.
@MainActor
public final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tracker: WindowTracker
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var refreshTimer: Timer?
    private var trackedWindows: [TrackedWindow] = []

    public var onShowOrphanedNotes: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init(tracker: WindowTracker) {
        self.tracker = tracker
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flipside"
        window.minSize = NSSize(width: 420, height: 320)
        // See BadgeWindowController: AppDelegate caches this controller and
        // reuses it across show() calls, so the default (true) would
        // double-release the window once the user closes it and the
        // (still-alive) controller is touched again.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startAutoRefresh()
    }

    public func refresh() {
        trackedWindows = tracker.currentWindows().sorted { $0.appName < $1.appName }
        statusLabel.stringValue = trackedWindows.isEmpty
            ? "Flipside is running. No windows tracked yet."
            : "Flipside is running. Tracking \(trackedWindows.count) window(s):"
        tableView.reloadData()
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func buildUI() {
        guard let window else { return }

        let iconView = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        iconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Flipside")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("trackedWindow"))
        column.title = "App — Window"
        column.width = 460
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
        let orphanedButton = NSButton(title: "Orphaned Notes…", target: self, action: #selector(orphanedNotesClicked))
        let quitButton = NSButton(title: "Quit Flipside", target: self, action: #selector(quitClicked))
        for button in [refreshButton, orphanedButton, quitButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        let buttonStack = NSStackView(views: [refreshButton, orphanedButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(statusLabel)
        container.addSubview(scrollView)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            scrollView.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        window.contentView = container
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        trackedWindows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let window = trackedWindows[row]
        let text = "\(window.appName) — \(window.title ?? "(no title)")"
        let identifier = NSUserInterfaceItemIdentifier("trackedWindowCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.stringValue = text
        return cell
    }

    @objc private func refreshClicked() {
        refresh()
    }

    @objc private func orphanedNotesClicked() {
        onShowOrphanedNotes?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}
