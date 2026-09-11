import XCTest
@testable import FlipsideCore

/// Thread-safe box for accumulating markers appended from debounced actions,
/// which may run on a queue other than the one that scheduled them.
final class DebouncerTestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    var snapshot: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class DebouncerTests: XCTestCase {

    func testSingleScheduleEventuallyFires() {
        let debouncer = Debouncer(delay: 0.05)
        let box = DebouncerTestBox()
        let expectation = expectation(description: "action fired")

        debouncer.schedule {
            box.append(1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(box.snapshot, [1])
    }

    func testRapidReschedulingOnlyFiresLastAction() {
        let debouncer = Debouncer(delay: 0.05)
        let box = DebouncerTestBox()
        let expectation = expectation(description: "second action fired")

        debouncer.schedule {
            box.append(1)
        }
        debouncer.schedule {
            box.append(2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(box.snapshot, [2], "only the second call's action should have fired; the first should have been cancelled")
    }
}
