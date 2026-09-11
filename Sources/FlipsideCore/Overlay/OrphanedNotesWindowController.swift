import AppKit

/// Surfaces Tier-3 (session-only) notes per Open Questions §12 item 1's
/// resolution: retained rather than discarded, shown in a simple list.
/// Read-only for v1 — manually promoting an orphaned note to a Tier-2 key
/// (as the spec allows in principle, §7) isn't implemented; this window is
/// purely for the user to see what's been kept.
@MainActor
public final class OrphanedNotesWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let window: NSWindow
    private let tableView = NSTableView()
    private var notes: [Note] = []

    public init(noteRepository: NoteRepository) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Orphaned Notes"

        super.init()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("orphanedNote"))
        column.title = "App — Note"
        column.width = 440
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        window.contentView = scrollView

        reload(from: noteRepository)
    }

    public func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func reload(from noteRepository: NoteRepository) {
        notes = (try? noteRepository.allNotes(tier: .session)) ?? []
        tableView.reloadData()
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        notes.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let note = notes[row]
        let trimmedBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmedBody.isEmpty ? "(empty note)" : String(trimmedBody.prefix(60))
        let text = "\(note.appName) — \(preview)"

        let identifier = NSUserInterfaceItemIdentifier("orphanedNoteCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.stringValue = text
        return cell
    }
}
