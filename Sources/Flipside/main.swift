import AppKit
import FlipsideCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let tracker = WindowTracker()
    private var overlayCoordinator: OverlayCoordinator?
    private var noteRepository: NoteRepository?
    private var orphanedNotesWindowController: OrphanedNotesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Flipside is a menu-bar-only accessory app: it never has a regular
        // visible window, which makes AppKit's automatic-termination feature
        // treat it as idle and silently kill it in the background. This is
        // exactly the "not seeing it" symptom — the process itself was being
        // reaped, not a rendering or permissions problem.
        ProcessInfo.processInfo.disableAutomaticTermination("Flipside runs as a menu-bar accessory with no regular windows")

        AccessibilityPermission.requestIfNeeded()

        let repository = Self.openNoteRepository()
        noteRepository = repository

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Flipside")
            symbol?.isTemplate = true
            button.image = symbol
            button.imagePosition = .imageOnly
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Orphaned Notes…", action: #selector(showOrphanedNotes), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Flipside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action == #selector(showOrphanedNotes) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item

        let coordinator = OverlayCoordinator(tracker: tracker, noteRepository: repository)
        overlayCoordinator = coordinator
        coordinator.start()
    }

    @objc private func showOrphanedNotes() {
        guard let repository = noteRepository else { return }
        let controller = orphanedNotesWindowController ?? OrphanedNotesWindowController(noteRepository: repository)
        controller.reload(from: repository)
        orphanedNotesWindowController = controller
        controller.show()
    }

    /// Opens the encrypted notes database at the spec-mandated path (§9.1),
    /// creating the containing directory and the SQLCipher key (via Keychain,
    /// §9.3) on first launch. Returns `nil` — running without persistence for
    /// this session, rather than crashing the whole app — if either step fails.
    private static func openNoteRepository() -> NoteRepository? {
        do {
            let supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Flipside", isDirectory: true)
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

            let dbPath = supportDir.appendingPathComponent("flipside.sqlite").path
            let key = try KeychainKeyStore.loadOrCreateKey()
            let database = try Database(path: dbPath, key: key)
            return NoteRepository(db: database)
        } catch {
            FileHandle.standardError.write(Data("Flipside: could not open notes database: \(error)\n".utf8))
            return nil
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
