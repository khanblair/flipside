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
    private var rescanTimer: Timer?
    public var onWindowsChanged: (() -> Void)?

    public init() {}

    public func start() {
        scanAllRunningApplications()
        startPeriodicRescan()
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
        // Switching Spaces — including in and out of a full-screened app,
        // which occupies its own Space — changes which windows are actually
        // on screen without any AX notification firing. Overlays have to be
        // re-evaluated or they linger over the wrong Space.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// A safety net for everything AX notifications miss: an app that wasn't
    /// Accessibility-ready when it launched (so observer registration failed),
    /// a window created before we started observing its app, or a window that
    /// vanished without posting a destroyed notification. Cheap enough at this
    /// interval for a personal-scale tool, and it makes tracking self-healing
    /// rather than dependent on every notification arriving.
    private func startPeriodicRescan() {
        rescanTimer?.invalidate()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rescanAllWindows()
            }
        }
    }

    /// Re-enumerates every app's windows, adding ones that appeared and
    /// dropping ones that are gone.
    public func rescanAllWindows() {
        var seen = Set<AXUIElement>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            guard let bundleID = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? bundleID
            for (axWindow, tracked) in AXWindowReader.windows(forPID: app.processIdentifier, bundleID: bundleID, appName: appName) {
                seen.insert(axWindow)
                registry.upsert(tracked, for: axWindow)
            }
            registerObserver(forPID: app.processIdentifier)
        }

        for (key, _) in registry.allKeyed() where !seen.contains(key) {
            registry.remove(for: key)
        }

        onWindowsChanged?()
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
            kAXWindowDeminiaturizedNotification,
            // An app posts didLaunchApplicationNotification before it has
            // created any windows, so enumerating at launch finds nothing.
            // Without this, a relaunched app is never picked up.
            kAXWindowCreatedNotification,
            // Titles change over a window's lifetime; the note attached to
            // the window has to follow, or it ends up stored under a stale key.
            kAXTitleChangedNotification
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
        case kAXWindowCreatedNotification:
            // The element is the new window; re-enumerate its app so the
            // window (and any siblings) get picked up immediately.
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else {
                onWindowsChanged?()
                return
            }
            trackWindows(pid: pid, bundleID: bundleID, appName: app.localizedName ?? bundleID)
            onWindowsChanged?()
        case kAXTitleChangedNotification:
            registry.updateTitle(AXWindowReader.title(of: element), for: element)
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

    @objc private func handleActiveSpaceChanged() {
        // A full-screened window's frame can also change as it enters or
        // leaves its Space, so re-enumerate rather than only re-evaluating
        // visibility.
        rescanAllWindows()
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
