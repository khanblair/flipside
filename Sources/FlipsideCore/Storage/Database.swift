import Foundation
@preconcurrency import CSQLCipher

/// Errors that can occur while opening or operating on an encrypted SQLCipher database.
public enum DatabaseError: Error {
    /// `sqlite3_open` itself failed (e.g. an unwritable path).
    case openFailed
    /// The database file could not be unlocked with the supplied key — either the key is
    /// wrong, or the file is not a valid (SQLCipher-encrypted) SQLite database.
    case keyRejected
    /// A SQL statement failed to execute; the associated string is sqlite's error message.
    case execFailed(String)
}

/// A thin wrapper around a single SQLCipher-encrypted SQLite connection.
///
/// On `init`, the connection is opened, the encryption key is applied via `PRAGMA key`
/// (which must happen before any other statement touches the database — see spec §9.3),
/// and the notes schema (spec §9.2) is created if it does not already exist.
public final class Database {
    private var handle: OpaquePointer?

    /// The raw sqlite3 connection handle, for use by repositories in this module that need
    /// to prepare their own statements.
    public var rawHandle: OpaquePointer? { handle }

    public init(path: String, key: Data) throws {
        var connection: OpaquePointer?
        let openResult = sqlite3_open(path, &connection)
        guard openResult == SQLITE_OK, let opened = connection else {
            if let connection {
                sqlite3_close(connection)
            }
            throw DatabaseError.openFailed
        }
        handle = opened

        // Apply the encryption key immediately, before any other statement — SQLCipher uses
        // this to unlock an existing encrypted file, or to initialize a brand new one.
        let hexKey = key.map { String(format: "%02x", $0) }.joined()
        try execute("PRAGMA key = \"x'\(hexKey)'\";")

        // SQLCipher does not validate the key at PRAGMA-key time — it only fails once a
        // statement actually has to read encrypted page content. Force that read now so a
        // wrong key surfaces immediately as `DatabaseError.keyRejected`, rather than
        // silently "succeeding" and failing later on an unrelated call.
        do {
            try execute("SELECT count(*) FROM sqlite_master;")
        } catch {
            throw DatabaseError.keyRejected
        }

        try execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id            TEXT PRIMARY KEY,
                identity_key  TEXT NOT NULL UNIQUE,
                identity_tier INTEGER NOT NULL,
                body          TEXT NOT NULL DEFAULT '',
                created_at    INTEGER NOT NULL,
                updated_at    INTEGER NOT NULL,
                bundle_id     TEXT NOT NULL,
                app_name      TEXT NOT NULL,
                last_title    TEXT,
                last_doc_path TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_notes_bundle ON notes(bundle_id);
            """)
    }

    /// Executes one or more semicolon-separated SQL statements with no bound parameters
    /// and no result handling. Intended for DDL and simple pragmas/administration; use a
    /// prepared statement (see `NoteRepository`) for anything taking parameters or rows.
    public func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite3_free(errorPointer)
            } else if let handle {
                message = String(cString: sqlite3_errmsg(handle))
            } else {
                message = "unknown sqlite error (code \(result))"
            }
            throw DatabaseError.execFailed(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }
}
