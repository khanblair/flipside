import AppKit

/// A borderless `NSWindow` that can still take keyboard focus.
///
/// `NSWindow` returns `false` from `canBecomeKey` for borderless windows.
/// A window that never becomes key never receives key events, so a text
/// view inside one looks focused (it even shows a caret) but silently
/// swallows everything typed. The note card is borderless by design
/// (spec §8.1) *and* needs typing, so it has to opt back in explicitly.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
