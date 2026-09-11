import XCTest
@testable import FlipsideCore

final class DatabaseTests: XCTestCase {
    private var tempPaths: [String] = []

    override func tearDown() {
        for path in tempPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        tempPaths.removeAll()
        super.tearDown()
    }

    private func makeTempPath() -> String {
        let path = NSTemporaryDirectory().appending("flipside-db-tests-\(UUID().uuidString).sqlite")
        tempPaths.append(path)
        return path
    }

    /// Opening a brand new database file with a key should succeed, and the
    /// schema from spec §9.2 should already exist (querying `notes` must not throw).
    func testOpeningNewDatabaseWithKeyCreatesSchema() throws {
        let path = makeTempPath()
        let key = Data(repeating: 0x42, count: 32)

        let db = try Database(path: path, key: key)

        try db.execute("SELECT * FROM notes;")
    }

    /// Opening the SAME encrypted file again with the WRONG key must fail.
    /// This is the one test that actually proves encryption is active rather
    /// than a no-op pragma being silently ignored.
    func testOpeningExistingDatabaseWithWrongKeyFails() throws {
        let path = makeTempPath()
        let correctKey = Data(repeating: 0x11, count: 32)
        let wrongKey = Data(repeating: 0x99, count: 32)

        do {
            let db = try Database(path: path, key: correctKey)
            try db.execute("""
                INSERT INTO notes (
                    id, identity_key, identity_tier, body, created_at, updated_at, bundle_id, app_name
                ) VALUES ('id-1', 'key-1', 1, 'hello', 1, 1, 'com.example', 'Example');
                """)
        }
        // `db` is deallocated at the end of the `do` scope above, closing the
        // underlying sqlite3 connection so the file can be reopened cleanly.

        XCTAssertThrowsError(try Database(path: path, key: wrongKey)) { error in
            XCTAssertTrue(error is DatabaseError, "Expected a DatabaseError, got \(error)")
        }
    }
}
