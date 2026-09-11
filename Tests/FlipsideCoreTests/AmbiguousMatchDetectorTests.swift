import XCTest
@testable import FlipsideCore

final class AmbiguousMatchDetectorTests: XCTestCase {

    private func makeNote(
        id: String,
        identityKey: String? = nil,
        identityTier: IdentityTier = .title,
        body: String = "body",
        createdAt: Int64 = 1_700_000_000,
        updatedAt: Int64 = 1_700_000_100,
        bundleID: String = "com.example.app",
        appName: String = "Example",
        lastTitle: String? = "Untitled",
        lastDocPath: String? = nil
    ) -> Note {
        Note(
            id: id,
            identityKey: identityKey ?? "com.example.app|Untitled",
            identityTier: identityTier,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            bundleID: bundleID,
            appName: appName,
            lastTitle: lastTitle,
            lastDocPath: lastDocPath
        )
    }

    func testEmptyCandidatesYieldsNone() {
        let result = AmbiguousMatchDetector.resolve(candidates: [])
        XCTAssertEqual(result, .none)
    }

    func testSingleCandidateYieldsUnambiguous() {
        let note = makeNote(id: "note-1")

        let result = AmbiguousMatchDetector.resolve(candidates: [note])

        XCTAssertEqual(result, .unambiguous(note))
    }

    func testMultipleCandidatesYieldsAmbiguousPreservingOrder() {
        let noteA = makeNote(id: "note-a", identityKey: "com.example.app|Untitled#1")
        let noteB = makeNote(id: "note-b", identityKey: "com.example.app|Untitled#2")

        let result = AmbiguousMatchDetector.resolve(candidates: [noteA, noteB])

        switch result {
        case .ambiguous(let notes):
            XCTAssertEqual(notes, [noteA, noteB])
        default:
            XCTFail("Expected .ambiguous, got \(result)")
        }
    }
}
