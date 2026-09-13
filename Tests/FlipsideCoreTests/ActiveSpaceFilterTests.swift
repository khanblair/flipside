import XCTest
@testable import FlipsideCore

/// Covers the Space-membership heuristic that keeps badges for windows on
/// other Spaces (notably full-screened apps, each of which gets its own
/// Space) from appearing over whatever the user is currently looking at.
final class ActiveSpaceFilterTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

    func testWindowPresentOnActiveSpaceIsVisible() {
        let onScreen = [ActiveSpaceFilter.OnScreenWindow(pid: 42, frame: frame)]

        XCTAssertTrue(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: onScreen))
    }

    func testWindowAbsentFromActiveSpaceIsNotVisible() {
        // The app is running and AX still reports its window, but nothing
        // matching is composited on this Space — e.g. it's full-screened on
        // another Space, or the user switched away.
        let onScreen = [ActiveSpaceFilter.OnScreenWindow(pid: 99, frame: frame)]

        XCTAssertFalse(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: onScreen))
    }

    func testSamePidButDifferentWindowDoesNotMatch() {
        // A multi-window app with one window here and another on a different
        // Space: matching on pid alone would wrongly show both badges.
        let otherWindow = CGRect(x: 2000, y: 50, width: 400, height: 300)
        let onScreen = [ActiveSpaceFilter.OnScreenWindow(pid: 42, frame: otherWindow)]

        XCTAssertFalse(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: onScreen))
    }

    func testSmallFrameDisagreementStillMatches() {
        // AX and CGWindowList can disagree by a point or two on the same
        // window; that must not read as "different window".
        let slightlyOff = CGRect(x: 102, y: 201, width: 799, height: 602)
        let onScreen = [ActiveSpaceFilter.OnScreenWindow(pid: 42, frame: slightlyOff)]

        XCTAssertTrue(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: onScreen))
    }

    func testLargeFrameDisagreementDoesNotMatch() {
        let wayOff = CGRect(x: 100, y: 200, width: 800, height: 400)
        let onScreen = [ActiveSpaceFilter.OnScreenWindow(pid: 42, frame: wayOff)]

        XCTAssertFalse(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: onScreen))
    }

    func testEmptyOnScreenListMeansNothingIsVisible() {
        XCTAssertFalse(ActiveSpaceFilter.isOnActiveSpace(pid: 42, frame: frame, onScreenWindows: []))
    }
}
