import CoreGraphics

/// Decides whether a tracked window is on the Space the user is currently
/// looking at.
///
/// This matters because of how macOS handles full screen: a full-screened app
/// is moved into its **own Space**, and the Accessibility API keeps reporting
/// windows from *every* Space regardless of which one is on screen. Without
/// filtering, badges for windows sitting on another Space appear floating over
/// whatever you're currently looking at, attached to nothing.
///
/// There is no shared identifier between an `AXUIElement` and a
/// `CGWindowList` entry, so membership is matched on owning process plus
/// approximate frame — the standard heuristic for correlating the two.
public enum ActiveSpaceFilter {
    /// A window currently composited on the active Space, as reported by
    /// `CGWindowList`. `frame` is in Cocoa screen coordinates, already
    /// converted from CoreGraphics' top-left origin.
    public struct OnScreenWindow: Equatable {
        public let pid: pid_t
        public let frame: CGRect

        public init(pid: pid_t, frame: CGRect) {
            self.pid = pid
            self.frame = frame
        }
    }

    /// Frames are compared with a small tolerance: AX and CGWindowList can
    /// disagree by a point or two on the same window, particularly mid-animation.
    public static let defaultTolerance: CGFloat = 6

    public static func isOnActiveSpace(
        pid: pid_t,
        frame: CGRect,
        onScreenWindows: [OnScreenWindow],
        tolerance: CGFloat = defaultTolerance
    ) -> Bool {
        onScreenWindows.contains { candidate in
            candidate.pid == pid && framesMatch(candidate.frame, frame, tolerance: tolerance)
        }
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
