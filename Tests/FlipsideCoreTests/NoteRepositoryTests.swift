import XCTest
@testable import FlipsideCore

final class NoteRepositoryTests: XCTestCase {
    private var tempPaths: [String] = []

    override func tearDown() {
        for path in tempPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        tempPaths.removeAll()
        super.tearDown()
    }

    private func makeRepository() throws -> NoteRepository {
        let path = NSTemporaryDirectory().appending("flipside-notes-tests-\(UUID().uuidString).sqlite")
        tempPaths.append(path)
        let key = Data(repeating: 0x7A, count: 32)
        let db = try Database(path: path, key: key)
        return NoteRepository(db: db)
    }

    private func makeNote(
        id: String = UUID().uuidString,
        identityKey: String,
        body: String = "hello world",
        bundleID: String = "com.example.app"
    ) -> Note {
        Note(
            id: id,
            identityKey: identityKey,
            identityTier: .title,
            body: body,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000,
            bundleID: bundleID,
            appName: "Example App",
            lastTitle: "My Window",
            lastDocPath: nil
        )
    }

    func testUpsertThenFindReturnsEqualNote() throws {
        let repo = try makeRepository()
        let note = makeNote(identityKey: "com.example.app::title::My Window")

        try repo.upsert(note)
        let found = try repo.findNote(identityKey: note.identityKey)

        XCTAssertEqual(found, note)
    }

    /// Upserting again with the same identityKey but a different body must
    /// update the existing row in place (honoring the UNIQUE constraint on
    /// identity_key) rather than inserting a duplicate row.
    func testUpsertWithSameIdentityKeyUpdatesRatherThanDuplicates() throws {
        let repo = try makeRepository()
        let identityKey = "com.example.app::title::My Window"
        let first = makeNote(identityKey: identityKey, body: "first body")
        try repo.upsert(first)

        var second = first
        second.body = "second body"
        second.updatedAt = first.updatedAt + 100
        second.lastTitle = "My Window (updated)"
        try repo.upsert(second)

        // A note in a different bundle, so the count below is only a pass if
        // `allNotes(bundleID:)` actually filters rather than just returning everything.
        try repo.upsert(makeNote(
            identityKey: "com.other.app::title::Other Window",
            bundleID: "com.other.app"
        ))

        let found = try repo.findNote(identityKey: identityKey)
        XCTAssertEqual(found?.body, "second body")
        XCTAssertEqual(found?.updatedAt, first.updatedAt + 100)
        XCTAssertEqual(found?.lastTitle, "My Window (updated)")

        let all = try repo.allNotes(bundleID: "com.example.app")
        XCTAssertEqual(all.count, 1)
    }

    func testFindNoteForUnknownKeyReturnsNil() throws {
        let repo = try makeRepository()

        let found = try repo.findNote(identityKey: "never-inserted-key")

        XCTAssertNil(found)
    }
}
