@preconcurrency import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Built on Carbon's `RegisterEventHotKey` rather than an `NSEvent` global
/// monitor, which looks like the modern choice but is the wrong tool here:
/// a global monitor can only *observe* keystrokes, so the frontmost app would
/// receive ⌃⌥F as well; it doesn't fire at all while Flipside is frontmost —
/// which it is whenever a note card is open, so the shortcut couldn't flip
/// back; and it requires Input Monitoring permission. A registered hot key
/// needs no permission, fires whichever app is in front, and consumes the
/// keystroke.
@MainActor
public final class GlobalHotKey {
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Returns `nil` if the shortcut couldn't be registered — most often
    /// because another app already owns the same key combination.
    public init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), handleHotKeyEvent, 1, &eventType, userData, &handlerRef) == noErr else {
            return nil
        }

        // A failed init still runs deinit once every property is set, so the
        // handler installed above is removed there rather than here.
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    fileprivate func fire() {
        action()
    }

    /// Four-character code identifying Flipside's hot keys: "FLPS".
    private static let signature: OSType = 0x464C_5053
}

/// Carbon delivers application-target events on the main thread, so running
/// the action on the main actor from here is sound.
private func handleHotKeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotKey.fire()
    }
    return noErr
}
