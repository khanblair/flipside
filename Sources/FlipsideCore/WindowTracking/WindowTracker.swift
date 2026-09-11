@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
public final class WindowTracker {
    private var registry = WindowRegistry<AXUIElement>()
    private var observers: [pid_t: AXObserver] = [:]
    public var onWindowsChanged: (() -> Void)?

    public init() {}

    public func start() {
        scanAllRunningApplications()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    public func scanAllRunningApplications() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            guard let bundleID = app.bundleIdentifier else { continue }
            trackWindows(pid: app.processIdentifier, bundleID: bundleID, appName: app.localizedName ?? bundleID)
        }
        onWindowsChanged?()
    }

    public func currentWindows() -> [TrackedWindow] {
        registry.all()
    }

    /// Windows paired with the live `AXUIElement` that identifies them for
    /// this session. Callers that must create/destroy per-window overlay
    /// state (badge/card pairs) need this key — `currentWindows()` alone
    /// can't tell two windows with identical field values apart.
    public func currentWindowsKeyed() -> [(AXUIElement, TrackedWindow)] {
        registry.allKeyed()
    }

    private func trackWindows(pid: pid_t, bundleID: String, appName: String) {
        for (axWindow, tracked) in AXWindowReader.windows(forPID: pid, bundleID: bundleID, appName: appName) {
            registry.upsert(tracked, for: axWindow)
        }
        registerObserver(forPID: pid)
    }

    private func registerObserver(forPID pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.handleAXNotification(element: element, notification: notification as String)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification
        ] {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func handleAXNotification(element: AXUIElement, notification: String) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            _ = registry.remove(for: element)
        case kAXMovedNotification, kAXResizedNotification:
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            var origin = CGPoint.zero
            var size = CGSize.zero
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
               let positionValue = positionRef {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
            }
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            registry.updateFrame(CGRect(origin: origin, size: size), for: element)
        default:
            break
        }
        onWindowsChanged?()
    }

    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        trackWindows(pid: app.processIdentifier, bundleID: bundleID, appName: app.localizedName ?? bundleID)
        onWindowsChanged?()
    }

    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observers.removeValue(forKey: app.processIdentifier)
        for window in registry.all() where window.pid == app.processIdentifier {
            _ = window
        }
        onWindowsChanged?()
    }
}
