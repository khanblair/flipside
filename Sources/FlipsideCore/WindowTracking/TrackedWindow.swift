import CoreGraphics

public struct TrackedWindow: Equatable, Sendable {
    public var pid: pid_t
    public var bundleID: String
    public var appName: String
    public var title: String?
    public var documentPath: String?
    public var frame: CGRect

    public init(pid: pid_t, bundleID: String, appName: String, title: String?, documentPath: String?, frame: CGRect) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.documentPath = documentPath
        self.frame = frame
    }
}
