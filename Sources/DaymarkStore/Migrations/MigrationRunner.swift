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

    /// Ordered migrations. Milestone 1 introduces notes, blocks, and a full-text index;
    /// Milestone 3 adds the tasks projection.
    public static let all: [Migration] = [
        Migration(version: 1, name: "001_initial_schema.sql", sql: initialSchema),
        Migration(version: 2, name: "002_note_search.sql", sql: noteSearch),
        Migration(version: 3, name: "003_tasks.sql", sql: tasks)
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

    // Tasks projected from Markdown checkbox lines. Like blocks, task rows are replaced on
    // every reprojection, so the table is a rebuildable projection of the files on disk.
    // `source_key` is a deterministic identity (note path + line + text) for rollover later.
    private static let tasks = """
    CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
        source_key TEXT NOT NULL,
        line_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        mentions TEXT NOT NULL DEFAULT '',
        due TEXT,
        section_heading TEXT,
        original_line TEXT NOT NULL,
        indexed_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_note_id ON tasks(note_id);
    CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    CREATE INDEX IF NOT EXISTS idx_tasks_source_key ON tasks(source_key);
    """
}
