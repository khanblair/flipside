import XCTest
import FlipsideCore

final class WindowRegistryTests: XCTestCase {

    private func makeWindow(
        pid: pid_t = 100,
        bundleID: String = "com.example.app",
        appName: String = "Example",
        title: String? = "Untitled",
        documentPath: String? = "/tmp/doc.txt",
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> TrackedWindow {
        TrackedWindow(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            title: title,
            documentPath: documentPath,
            frame: frame
        )
    }

    func testUpsertThenAllReturnsExactlyThatWindow() {
        var registry = WindowRegistry<String>()
        let window = makeWindow()

        registry.upsert(window, for: "key-1")

        XCTAssertEqual(registry.all(), [window])
    }

    func testUpdateFrameMutatesOnlyFrameOfExistingEntry() {
        var registry = WindowRegistry<String>()
        let original = makeWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        registry.upsert(original, for: "key-1")

        let newFrame = CGRect(x: 10, y: 20, width: 300, height: 400)
        registry.updateFrame(newFrame, for: "key-1")

        var expected = original
        expected.frame = newFrame
        XCTAssertEqual(registry.all(), [expected])
    }

    func testUpdateFrameOnMissingKeyIsANoOp() {
        var registry = WindowRegistry<String>()

        registry.updateFrame(CGRect(x: 1, y: 2, width: 3, height: 4), for: "missing")

        XCTAssertTrue(registry.all().isEmpty)
    }

    func testUpsertingSameKeyTwiceUpdatesInPlace() {
        var registry = WindowRegistry<String>()
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second", frame: CGRect(x: 5, y: 5, width: 50, height: 50))

        registry.upsert(first, for: "key-1")
        registry.upsert(second, for: "key-1")

        XCTAssertEqual(registry.all(), [second])
    }

    func testRemoveReturnsTheRemovedWindowAndItIsGoneAfterward() {
        var registry = WindowRegistry<String>()
        let window = makeWindow()
        registry.upsert(window, for: "key-1")

        let removed = registry.remove(for: "key-1")

        XCTAssertEqual(removed, window)
        XCTAssertTrue(registry.all().isEmpty)
    }

    func testRemoveOnNonexistentKeyReturnsNilWithoutCrashing() {
        var registry = WindowRegistry<String>()

        let removed = registry.remove(for: "nonexistent")

        XCTAssertNil(removed)
    }

    func testAllKeyedReturnsEachWindowPairedWithItsKey() {
        var registry = WindowRegistry<String>()
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        registry.upsert(first, for: "key-1")
        registry.upsert(second, for: "key-2")

        let keyed = Dictionary(uniqueKeysWithValues: registry.allKeyed())

        XCTAssertEqual(keyed["key-1"], first)
        XCTAssertEqual(keyed["key-2"], second)
        XCTAssertEqual(keyed.count, 2)
    }
}
