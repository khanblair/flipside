import XCTest
import AppKit
@testable import FlipsideCore

/// Regression test for a real bug found while testing the built app: AX
/// coordinates (origin top-left, Y down) were being fed straight into
/// AppKit APIs that expect Cocoa screen coordinates (origin bottom-left,
/// Y up), so every badge landed at the vertically mirrored wrong spot on
/// screen instead of the tracked window's actual corner.
final class AXWindowReaderTests: XCTestCase {
    func testConvertAXRectToCocoaFlipsYRelativeToMainScreenHeight() throws {
        guard let screenHeight = NSScreen.screens.first?.frame.height else {
            throw XCTSkip("No screen available in this environment")
        }
        let axOrigin = CGPoint(x: 50, y: 100)
        let size = CGSize(width: 400, height: 300)

        let cocoaRect = AXWindowReader.convertAXRectToCocoa(origin: axOrigin, size: size)

        XCTAssertEqual(cocoaRect.origin.x, 50, accuracy: 0.001)
        XCTAssertEqual(cocoaRect.origin.y, screenHeight - 100 - 300, accuracy: 0.001)
        XCTAssertEqual(cocoaRect.size.width, size.width, accuracy: 0.001)
        XCTAssertEqual(cocoaRect.size.height, size.height, accuracy: 0.001)
    }

    func testWindowAtAXTopLeftOfScreenLandsAtTopOfCocoaSpace() throws {
        guard let screenHeight = NSScreen.screens.first?.frame.height else {
            throw XCTSkip("No screen available in this environment")
        }
        let size = CGSize(width: 200, height: 100)

        let cocoaRect = AXWindowReader.convertAXRectToCocoa(origin: .zero, size: size)

        // A window whose AX top-left is at the very top of the screen must
        // land with its Cocoa origin.y at screenHeight - windowHeight — the
        // top of Cocoa's bottom-left-origin space — not near y=0 (the
        // bottom), which is what the unconverted bug produced.
        XCTAssertEqual(cocoaRect.origin.y, screenHeight - size.height, accuracy: 0.001)
    }
}
