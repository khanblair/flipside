import Foundation
@preconcurrency import CSQLCipher

/// `SQLITE_TRANSIENT` is defined in `sqlite3.h` as a macro that casts `-1` to
/// `sqlite3_destructor_type` (a C function pointer type). The Clang importer can't expose a
/// pointer-cast macro as a usable Swift symbol, so it's reconstructed here exactly as
/// SQLite's own documentation recommends for Swift callers. It tells `sqlite3_bind_text`
/// to make its own private copy of the string immediately, which is what lets us bind from
/// a short-lived `withCString` buffer below.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// CRUD access to the `notes` table (spec §9.2) over a single `Database` connection.
public final class NoteRepository {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Inserts a new note, or — if a row with the same `identity_key` already exists —
    /// updates its mutable fields in place. `identity_key` is UNIQUE, so this is what
    /// keeps a window's note as a single row across repeated flips/edits.
    public func upsert(_ note: Note) throws {
        let sql = """
            INSERT INTO notes (
                id, identity_key, identity_tier, body, created_at, updated_at,
                bundle_id, app_name, last_title, last_doc_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(identity_key) DO UPDATE SET
                body = excluded.body,
                updated_at = excluded.updated_at,
                last_title = excluded.last_title,
                last_doc_path = excluded.last_doc_path;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, 1, note.id)
        Self.bindText(stmt, 2, note.identityKey)
        sqlite3_bind_int(stmt, 3, Int32(note.identityTier.rawValue))
        Self.bindText(stmt, 4, note.body)
        sqlite3_bind_int64(stmt, 5, note.createdAt)
        sqlite3_bind_int64(stmt, 6, note.updatedAt)
        Self.bindText(stmt, 7, note.bundleID)
        Self.bindText(stmt, 8, note.appName)
        Self.bindTextOrNull(stmt, 9, note.lastTitle)
        Self.bindTextOrNull(stmt, 10, note.lastDocPath)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
        }
    }

    /// Looks up the note attached to a given window identity key (spec §7), if any.
    public func findNote(identityKey: String) throws -> Note? {
        let sql = """
            SELECT id, identity_key, identity_tier, body, created_at, updated_at,
                   bundle_id, app_name, last_title, last_doc_path
            FROM notes WHERE identity_key = ? LIMIT 1;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, 1, identityKey)

        let stepResult = sqlite3_step(stmt)
        switch stepResult {
        case SQLITE_ROW:
            return Self.note(from: stmt)
        case SQLITE_DONE:
            return nil
        default:
            throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
        }
    }

    /// All notes for a given app (spec §9.2's `idx_notes_bundle` index), e.g. to show every
    /// note belonging to one bundle ID.
    public func allNotes(bundleID: String) throws -> [Note] {
        let sql = """
            SELECT id, identity_key, identity_tier, body, created_at, updated_at,
                   bundle_id, app_name, last_title, last_doc_path
            FROM notes WHERE bundle_id = ?;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, 1, bundleID)

        var results: [Note] = []
        loop: while true {
            let stepResult = sqlite3_step(stmt)
            switch stepResult {
            case SQLITE_ROW:
                results.append(Self.note(from: stmt))
            case SQLITE_DONE:
                break loop
            default:
                throw DatabaseError.execFailed(Self.errorMessage(db.rawHandle))
            }
        }
        return results
    }

    /// Stored notes for `bundleID` whose last-seen title matches a generic
    /// pattern ("Untitled", "Untitled 2", etc.) — the candidate pool for the
    /// conservative ambiguous-match rule (spec §7/§12 item 1; see
    /// `AmbiguousMatchDetector`). Exact identity-key lookups can only ever
    /// return 0 or 1 rows (the key is UNIQUE), so this is the one place real
    /// ambiguity can arise: several old notes with generic titles are all
    /// equally plausible matches for a newly-appeared, generically-titled
    /// window. Titles that aren't generic are never included, since sweeping
    /// them in would defeat the point of treating only truly ambiguous
    /// titles specially.
    public func notesWithGenericTitle(bundleID: String) throws -> [Note] {
        try allNotes(bundleID: bundleID).filter { note in
            guard let title = note.lastTitle else { return false }
            return title.range(of: Self.genericTitlePattern, options: .regularExpression) != nil
        }
    }

    private static let genericTitlePattern = "^Untitled( \\d+)?$"

    // MARK: - Binding / row-decoding helpers

    private static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        _ = value.withCString { cString in
            sqlite3_bind_text(stmt, index, cString, -1, SQLITE_TRANSIENT)
        }
    }

    private static func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func note(from stmt: OpaquePointer?) -> Note {
        Note(
            id: columnText(stmt, 0),
            identityKey: columnText(stmt, 1),
            identityTier: IdentityTier(rawValue: Int(sqlite3_column_int(stmt, 2))) ?? .session,
            body: columnText(stmt, 3),
            createdAt: sqlite3_column_int64(stmt, 4),
            updatedAt: sqlite3_column_int64(stmt, 5),
            bundleID: columnText(stmt, 6),
            appName: columnText(stmt, 7),
            lastTitle: columnTextOrNil(stmt, 8),
            lastDocPath: columnTextOrNil(stmt, 9)
        )
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private static func columnTextOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private static func errorMessage(_ handle: OpaquePointer?) -> String {
        guard let handle else { return "unknown sqlite error" }
        return String(cString: sqlite3_errmsg(handle))
    }
}
