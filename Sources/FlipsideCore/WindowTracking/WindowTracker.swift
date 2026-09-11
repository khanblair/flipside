@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
public final class WindowTracker {
    private var registry = WindowRegistry<AXUIElement>()
    private var observers: [pid_t: AXObserver] = [:]
    // Rapid window churn (e.g. browser tabs opening as new windows, or a
    // window being dragged) can fire many move/resize notifications per
    // second; coalescing the resulting overlay-resync notification avoids
    // the badge/card lag called out in spec §14's risk table.
    private let moveResizeDebouncer = Debouncer(delay: 0.05)
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
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ] {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func handleAXNotification(element: AXUIElement, notification: String) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            // Explicit, immediate teardown — never debounced, so overlays
            // never linger on a window that's already gone (spec §14).
            _ = registry.remove(for: element)
            onWindowsChanged?()
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
            registry.updateFrame(AXWindowReader.convertAXRectToCocoa(origin: origin, size: size), for: element)
            moveResizeDebouncer.schedule { [weak self] in
                Task { @MainActor in
                    self?.onWindowsChanged?()
                }
            }
        case kAXWindowMiniaturizedNotification:
            registry.updateMinimized(true, for: element)
            onWindowsChanged?()
        case kAXWindowDeminiaturizedNotification:
            registry.updateMinimized(false, for: element)
            onWindowsChanged?()
        default:
            onWindowsChanged?()
        }
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
