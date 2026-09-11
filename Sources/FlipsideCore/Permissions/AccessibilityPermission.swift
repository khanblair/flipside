@preconcurrency import ApplicationServices

public enum AccessibilityPermission {
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
