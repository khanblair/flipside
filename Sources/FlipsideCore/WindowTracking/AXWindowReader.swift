import AppKit
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

        return Self.convertAXRectToCocoa(origin: origin, size: size)
    }

    /// The Accessibility API reports positions in "global display
    /// coordinates": origin at the top-left of the screen, Y increasing
    /// downward. AppKit's screen coordinate system (what `NSWindow.
    /// setFrameOrigin`/`setFrame` expect) has origin at the bottom-left,
    /// Y increasing upward. Feeding an unconverted AX rect straight into an
    /// `NSWindow` places it at the vertically mirrored wrong spot on
    /// screen — this conversion is what makes the two systems agree.
    static func convertAXRectToCocoa(origin: CGPoint, size: CGSize) -> CGRect {
        guard let mainScreenHeight = NSScreen.screens.first?.frame.height else {
            return CGRect(origin: origin, size: size)
        }
        let flippedY = mainScreenHeight - origin.y - size.height
        return CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)
    }
}
