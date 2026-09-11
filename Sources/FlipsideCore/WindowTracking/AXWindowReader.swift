import ApplicationServices
import CoreGraphics

@preconcurrency import ApplicationServices

enum AXWindowReader {
    static func windows(forPID pid: pid_t, bundleID: String, appName: String) -> [(AXUIElement, TrackedWindow)] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }

        return axWindows.map { axWindow in
            (axWindow, TrackedWindow(
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                title: stringAttribute(axWindow, kAXTitleAttribute),
                documentPath: stringAttribute(axWindow, kAXDocumentAttribute),
                frame: frameAttribute(axWindow),
                isMinimized: boolAttribute(axWindow, kAXMinimizedAttribute)
            ))
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    private static func frameAttribute(_ element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero

        var positionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
           let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        }

        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: origin, size: size)
    }
}
