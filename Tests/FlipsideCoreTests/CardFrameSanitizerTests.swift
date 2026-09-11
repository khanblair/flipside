import XCTest
@testable import FlipsideCore

final class CardFrameSanitizerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testFrameFullyOnScreenPassesThroughUnchanged() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)

        let result = CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen])

        XCTAssertEqual(result, frame)
    }

    func testFrameExtendingPastScreenIsClampedToScreen() {
        let frame = CGRect(x: 1200, y: 100, width: 800, height: 400)

        let result = CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen])

        // Only the on-screen portion remains, so the card can never sprawl
        // beyond the display it belongs to.
        XCTAssertEqual(result, CGRect(x: 1200, y: 100, width: 240, height: 400))
    }

    func testZeroSizedFrameIsRejected() {
        XCTAssertNil(CardFrameSanitizer.sanitized(.zero, visibleScreenFrames: [screen]))
    }

    func testTinyFrameIsRejected() {
        let frame = CGRect(x: 10, y: 10, width: 40, height: 30)

        XCTAssertNil(CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen]))
    }

    func testFullyOffscreenFrameIsRejected() {
        let frame = CGRect(x: 5000, y: 5000, width: 600, height: 400)

        XCTAssertNil(CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen]))
    }

    func testFrameIsClampedToTheScreenItMostlyOccupies() {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        // Mostly on the second screen, slightly overlapping the first.
        let frame = CGRect(x: 1400, y: 100, width: 900, height: 500)

        let result = CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen, secondScreen])

        XCTAssertEqual(result, frame.intersection(secondScreen))
    }

    func testNonFiniteFrameIsRejected() {
        let frame = CGRect(x: CGFloat.nan, y: 0, width: 600, height: 400)

        XCTAssertNil(CardFrameSanitizer.sanitized(frame, visibleScreenFrames: [screen]))
    }
}
