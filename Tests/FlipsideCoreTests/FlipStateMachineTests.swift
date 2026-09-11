import XCTest
@testable import FlipsideCore

final class FlipStateMachineTests: XCTestCase {
    func testInitialStateIsFront() {
        let machine = FlipStateMachine()
        XCTAssertEqual(machine.state, .front)
    }

    func testToggleAlternatesBetweenFrontAndBack() {
        let machine = FlipStateMachine()

        let first = machine.toggle()
        XCTAssertEqual(first, .back)
        XCTAssertEqual(machine.state, .back)

        let second = machine.toggle()
        XCTAssertEqual(second, .front)
        XCTAssertEqual(machine.state, .front)
    }
}
