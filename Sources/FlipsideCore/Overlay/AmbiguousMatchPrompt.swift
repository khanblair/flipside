import AppKit

/// Spec §7: "When Flipside detects an ambiguous match... it does not
/// silently guess — it prompts the user to confirm which note (if any)
/// belongs to the new window." A thin modal-alert adapter around that
/// decision — not unit tested (there's no way to drive a real `NSAlert`
/// modal loop headlessly); the decision logic it wraps
/// (`AmbiguousMatchDetector`) is tested on its own.
@MainActor
public enum AmbiguousMatchPrompt {
    /// Shows a blocking alert listing each candidate note (by a short body
    /// preview) plus a "start a new note" option. Returns the chosen note,
    /// or `nil` if the user picked "start a new note" or dismissed the alert.
    public static func choose(candidates: [Note], windowTitle: String) -> Note? {
        guard !candidates.isEmpty else { return nil }

        let alert = NSAlert()
        alert.messageText = "Multiple notes might belong to this window"
        alert.informativeText = """
            "\(windowTitle)" has more than one previously saved note with a similar, generic title. \
            Choose which one belongs here, or start a new note.
            """

        for (index, note) in candidates.enumerated() {
            let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.isEmpty ? "(empty note)" : String(trimmed.prefix(40))
            alert.addButton(withTitle: "\(index + 1). \(preview)")
        }
        alert.addButton(withTitle: "Start a new note")

        let response = alert.runModal()
        let chosenIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard chosenIndex >= 0, chosenIndex < candidates.count else {
            return nil
        }
        return candidates[chosenIndex]
    }
}
