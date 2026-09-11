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

    /// Supports the conservative ambiguous-match rule (Task 17/18): when a
    /// newly-appeared window has a generic title ("Untitled", "Untitled 2",
    /// etc.), any stored note for the same bundle with a similarly generic
    /// title is a plausible reattachment candidate — titles that aren't
    /// generic must never be swept in, since that would defeat the point of
    /// treating only truly ambiguous titles specially.
    func testNotesWithGenericTitleReturnsOnlyGenericallyTitledNotesForThatBundle() throws {
        let repo = try makeRepository()
        var untitled = makeNote(identityKey: "com.example.app::title::Untitled", body: "a")
        untitled.lastTitle = "Untitled"
        var untitled2 = makeNote(identityKey: "com.example.app::title::Untitled 2", body: "b")
        untitled2.lastTitle = "Untitled 2"
        var namedDoc = makeNote(identityKey: "com.example.app::title::My Doc", body: "c")
        namedDoc.lastTitle = "My Doc"
        var otherBundleUntitled = makeNote(
            identityKey: "com.other.app::title::Untitled",
            body: "d",
            bundleID: "com.other.app"
        )
        otherBundleUntitled.lastTitle = "Untitled"

        try repo.upsert(untitled)
        try repo.upsert(untitled2)
        try repo.upsert(namedDoc)
        try repo.upsert(otherBundleUntitled)

        let candidates = try repo.notesWithGenericTitle(bundleID: "com.example.app")

        XCTAssertEqual(Set(candidates.map(\.identityKey)), [untitled.identityKey, untitled2.identityKey])
    }
}
