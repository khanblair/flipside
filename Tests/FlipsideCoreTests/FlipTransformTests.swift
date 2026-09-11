import XCTest
import QuartzCore
@testable import FlipsideCore

final class FlipTransformTests: XCTestCase {
    func testZeroAngleIsApproximatelyIdentityRotation() {
        let t = FlipTransform.transform(angleDegrees: 0, perspectiveDistance: 1000)
        XCTAssertEqual(t.m11, 1, accuracy: 0.0001)
    }

    func testPerspectiveDistanceSetsM34Exactly() {
        // angleDegrees: 0 keeps the Y-axis rotation an identity multiply, so m34
        // isn't scaled by cos(angle) and the equality holds exactly.
        let distance: CGFloat = 500
        let t = FlipTransform.transform(angleDegrees: 0, perspectiveDistance: distance)
        XCTAssertEqual(t.m34, -1.0 / distance)
    }

    func testNinetyDegreesCollapsesM11ToApproximatelyZero() {
        let t = FlipTransform.transform(angleDegrees: 90, perspectiveDistance: 1000)
        XCTAssertEqual(t.m11, 0, accuracy: 0.0001)
    }
}
