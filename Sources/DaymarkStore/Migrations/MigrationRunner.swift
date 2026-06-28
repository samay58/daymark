import Foundation

public struct Migration: Equatable, Sendable {
    public let version: Int
    public let name: String
    public let sql: String

    public init(version: Int, name: String, sql: String) {
        self.version = version
        self.name = name
        self.sql = sql
    }
}

public struct MigrationRunner {
    public init() {}

    /// Ordered migrations. Milestone 1 introduces notes, blocks, and a full-text index.
    public static let all: [Migration] = [
        Migration(version: 1, name: "001_initial_schema.sql", sql: initialSchema),
        Migration(version: 2, name: "002_note_search.sql", sql: noteSearch)
    ]

    public func allMigrations() -> [Migration] { Self.all }

    /// Migrations not yet recorded in `schema_migrations`.
    public func pendingMigrations(appliedVersions: Set<Int>) -> [Migration] {
        Self.all.filter { !appliedVersions.contains($0.version) }
    }

    /// Names of migrations pending against an empty database.
    public func pendingMigrationNames() -> [String] {
        Self.all.map(\.name)
    }

    private static let initialSchema = """
    CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rel_path TEXT NOT NULL UNIQUE,
        title TEXT,
        content_hash TEXT NOT NULL,
        byte_count INTEGER NOT NULL,
        modified_at TEXT,
        indexed_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        line_start INTEGER NOT NULL,
        line_end INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_blocks_note_id ON blocks(note_id);
    """

    // FTS5 over note title and body. The note row remains the system of record for
    // metadata; this virtual table is a rebuildable projection used only for search.
    private static let noteSearch = """
    CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
        rel_path UNINDEXED,
        title,
        body,
        tokenize = 'unicode61'
    );
    """
}
