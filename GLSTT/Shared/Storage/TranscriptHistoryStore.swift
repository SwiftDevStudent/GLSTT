import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class TranscriptHistoryStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(filename: String) {
        databaseURL = Self.databaseURL(for: filename)
        openDatabase()
        createTableIfNeeded()
    }

    deinit {
        sqlite3_close(database)
    }

    func loadEntries() -> [TranscriptHistoryEntry] {
        let query = """
        SELECT id, text, created_at
        FROM transcript_history
        ORDER BY created_at DESC
        """

        guard let statement = prepareStatement(query) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var entries: [TranscriptHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idCString = sqlite3_column_text(statement, 0),
                let textCString = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let idString = String(cString: idCString)
            let text = String(cString: textCString)
            let createdAt = sqlite3_column_double(statement, 2)

            guard let id = UUID(uuidString: idString) else {
                continue
            }

            entries.append(
                TranscriptHistoryEntry(
                    id: id,
                    text: text,
                    timestamp: Date(timeIntervalSince1970: createdAt)
                )
            )
        }

        return entries
    }

    func save(_ entry: TranscriptHistoryEntry) {
        let deleteSQL = "DELETE FROM transcript_history WHERE text = ?"
        guard let deleteStatement = prepareStatement(deleteSQL) else {
            return
        }
        bind(entry.text, at: 1, in: deleteStatement)
        _ = sqlite3_step(deleteStatement)
        sqlite3_finalize(deleteStatement)

        let insertSQL = """
        INSERT INTO transcript_history (id, text, created_at)
        VALUES (?, ?, ?)
        """

        guard let insertStatement = prepareStatement(insertSQL) else {
            return
        }
        defer { sqlite3_finalize(insertStatement) }

        bind(entry.id.uuidString, at: 1, in: insertStatement)
        bind(entry.text, at: 2, in: insertStatement)
        sqlite3_bind_double(insertStatement, 3, entry.timestamp.timeIntervalSince1970)
        _ = sqlite3_step(insertStatement)
    }

    private func openDatabase() {
        let directory = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sqlite3_open(databaseURL.path, &database)
    }

    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS transcript_history (
            id TEXT PRIMARY KEY NOT NULL,
            text TEXT NOT NULL,
            created_at DOUBLE NOT NULL
        )
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func prepareStatement(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
    }

    private static func databaseURL(for filename: String) -> URL {
        let supportDirectory =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return supportDirectory.appendingPathComponent("GLSTT", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
