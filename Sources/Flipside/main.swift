import AppKit
import FlipsideCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let tracker = WindowTracker()
    private var overlayCoordinator: OverlayCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityPermission.requestIfNeeded()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🗂"
        statusItem = item

        let coordinator = OverlayCoordinator(tracker: tracker, noteRepository: Self.openNoteRepository())
        overlayCoordinator = coordinator
        coordinator.start()
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
