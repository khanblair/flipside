import CoreGraphics

public struct TrackedWindow: Equatable, Sendable {
    public var pid: pid_t
    public var bundleID: String
    public var appName: String
    public var title: String?
    public var documentPath: String?
    public var frame: CGRect
    /// Per Open Questions §12 item 2: minimized windows hide their badge
    /// rather than shrinking into the Dock region (the spec's stated
    /// leaning, taken as the v1 behavior — see Task 22).
    public var isMinimized: Bool

    public init(
        pid: pid_t,
        bundleID: String,
        appName: String,
        title: String?,
        documentPath: String?,
        frame: CGRect,
        isMinimized: Bool = false
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.documentPath = documentPath
        self.frame = frame
        self.isMinimized = isMinimized
    }
}
