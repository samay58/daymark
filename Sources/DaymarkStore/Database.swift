import Foundation
import SQLite3
import DaymarkCore

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct DatabaseConfiguration: Equatable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public enum StoreError: Error, CustomStringConvertible {
    case open(String)
    case notOpen
    case sql(String)

    public var description: String {
        switch self {
        case .open(let message): return "database open failed: \(message)"
        case .notOpen: return "database is not open"
        case .sql(let message): return "sql error: \(message)"
        }
    }
}

/// A record projected from a Markdown note. SQLite is an index and projection;
/// Markdown files remain the source of truth.
public struct NoteRecord: Equatable, Sendable {
    public var id: Int64
    public var relativePath: String
    public var title: String?
    public var contentHash: String
    public var byteCount: Int
    public var modifiedAt: String?
    public var indexedAt: String
}

/// A local full-text search result. `snippet` is a short body excerpt around the match.
public struct SearchHit: Equatable, Sendable {
    public var relativePath: String
    public var title: String?
    public var snippet: String

    public init(relativePath: String, title: String?, snippet: String) {
        self.relativePath = relativePath
        self.title = title
        self.snippet = snippet
    }
}

public struct RolloverRecord: Equatable, Sendable {
    public var sourceKey: String
    public var sourceNotePath: String
    public var sourceLineNumber: Int
    public var sourceTitle: String
    public var targetNotePath: String
    public var marker: String

    public init(
        sourceKey: String,
        sourceNotePath: String,
        sourceLineNumber: Int,
        sourceTitle: String,
        targetNotePath: String,
        marker: String
    ) {
        self.sourceKey = sourceKey
        self.sourceNotePath = sourceNotePath
        self.sourceLineNumber = sourceLineNumber
        self.sourceTitle = sourceTitle
        self.targetNotePath = targetNotePath
        self.marker = marker
    }
}

public actor Database {
    public nonisolated let configuration: DatabaseConfiguration
    private var handle: OpaquePointer?
    private let migrations = MigrationRunner()

    public init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
    }

    public func open() throws {
        guard handle == nil else { return }
        let directory = (configuration.path as NSString).deletingLastPathComponent
        if !directory.isEmpty, !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let result = sqlite3_open_v2(configuration.path, &connection, flags, nil)
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            sqlite3_close(connection)
            throw StoreError.open(message)
        }
        handle = connection
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        // Independent connections (app + CLI) can write concurrently under WAL. Wait briefly
        // for a contended writer instead of failing immediately with SQLITE_BUSY.
        try exec("PRAGMA busy_timeout=5000;")
    }

    public func close() {
        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }

    @discardableResult
    public func migrate() throws -> [String] {
        let connection = try requireHandle()
        try exec("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at TEXT NOT NULL
        );
        """)

        let appliedVersions = try queryInts("SELECT version FROM schema_migrations;")
        let pending = migrations.pendingMigrations(appliedVersions: Set(appliedVersions))
        guard !pending.isEmpty else { return [] }

        try exec("BEGIN;")
        do {
            let stamp = Self.timestamp()
            for migration in pending {
                try exec(migration.sql)
                let insert = try prepare("INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);")
                defer { sqlite3_finalize(insert) }
                sqlite3_bind_int(insert, 1, Int32(migration.version))
                sqlite3_bind_text(insert, 2, migration.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insert, 3, stamp, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
                }
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        return pending.map(\.name)
    }

    public func appliedMigrationNames() throws -> [String] {
        try queryStrings("SELECT name FROM schema_migrations ORDER BY version;")
    }

    public func tableNames() throws -> [String] {
        try queryStrings("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    }

    /// Projects a note's row, search index, blocks, and tasks as one atomic unit. The
    /// whole upsert runs in a single transaction so a mid-sequence failure rolls back
    /// instead of leaving SQLite internally inconsistent (a note without its blocks, or
    /// a stale FTS row). The consistency boundary lives here in the actor, not in the
    /// repository facade. Reprojection stays idempotent: blocks and tasks are replaced,
    /// never appended.
    public func replaceNoteProjection(
        relativePath: String,
        title: String?,
        content: String,
        modifiedAt: Date?,
        blocks: [Block],
        tasks: [TaskItem]
    ) throws {
        try withTransaction {
            let id = try upsertNote(
                relativePath: relativePath,
                title: title,
                content: content,
                modifiedAt: modifiedAt
            )
            try replaceBlocks(noteID: id, blocks: blocks)
            try replaceTasks(noteID: id, tasks: tasks)
        }
    }

    /// Upserts a note row keyed by its workspace-relative path, preserving the row id
    /// (and therefore its blocks) on update. Returns the note id.
    @discardableResult
    public func upsertNote(
        relativePath: String,
        title: String?,
        content: String,
        modifiedAt: Date?
    ) throws -> Int64 {
        let connection = try requireHandle()
        let contentHash = ContentHasher.hash(content)
        let byteCount = Int32(content.utf8.count)
        let modified = modifiedAt.map(Self.timestamp(from:))
        let indexedAt = Self.timestamp()

        let sql = """
        INSERT INTO notes (rel_path, title, content_hash, byte_count, modified_at, indexed_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(rel_path) DO UPDATE SET
            title=excluded.title,
            content_hash=excluded.content_hash,
            byte_count=excluded.byte_count,
            modified_at=excluded.modified_at,
            indexed_at=excluded.indexed_at;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, relativePath, -1, SQLITE_TRANSIENT)
        bindOptionalText(statement, 2, title)
        sqlite3_bind_text(statement, 3, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, byteCount)
        bindOptionalText(statement, 5, modified)
        sqlite3_bind_text(statement, 6, indexedAt, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }

        try refreshSearchIndex(relativePath: relativePath, title: title, body: content)

        let ids = try queryInts("SELECT id FROM notes WHERE rel_path = ?;", text: relativePath)
        return Int64(ids.first ?? 0)
    }

    /// Rewrites the FTS row for a note. Delete-then-insert keeps the search index in
    /// lockstep with the latest content without relying on FTS5 external-content triggers.
    private func refreshSearchIndex(relativePath: String, title: String?, body: String) throws {
        let connection = try requireHandle()
        let delete = try prepare("DELETE FROM notes_fts WHERE rel_path = ?;")
        sqlite3_bind_text(delete, 1, relativePath, -1, SQLITE_TRANSIENT)
        let deleted = sqlite3_step(delete)
        sqlite3_finalize(delete)
        guard deleted == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }

        let insert = try prepare("INSERT INTO notes_fts (rel_path, title, body) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_text(insert, 1, relativePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insert, 2, title ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insert, 3, body, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(insert) == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }
    }

    /// Local full-text search across note titles and bodies, ranked by FTS5 relevance.
    /// Free-text input is tokenized into prefix terms, so partial words match as you type.
    public func search(_ query: String, limit: Int = 20) throws -> [SearchHit] {
        let match = Self.matchExpression(from: query)
        guard !match.isEmpty else { return [] }

        let statement = try prepare("""
        SELECT rel_path, title, snippet(notes_fts, 2, '', '', '…', 12)
        FROM notes_fts
        WHERE notes_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var hits: [SearchHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let relativePath = columnText(statement, 0) ?? ""
            let titleValue = columnText(statement, 1)
            hits.append(SearchHit(
                relativePath: relativePath,
                title: (titleValue?.isEmpty == false) ? titleValue : nil,
                snippet: columnText(statement, 2) ?? ""
            ))
        }
        return hits
    }

    /// Turns free text into a safe FTS5 MATCH expression: each whitespace-separated token
    /// becomes a quoted prefix term joined by implicit AND. Quoting neutralizes FTS
    /// operators so user input cannot form an invalid query.
    static func matchExpression(from query: String) -> String {
        query
            .split { $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")
    }

    /// Replaces all blocks for a note. Reprojecting a note never appends.
    public func replaceBlocks(noteID: Int64, blocks: [Block]) throws {
        let connection = try requireHandle()
        let delete = try prepare("DELETE FROM blocks WHERE note_id = ?;")
        sqlite3_bind_int64(delete, 1, noteID)
        let deleted = sqlite3_step(delete)
        sqlite3_finalize(delete)
        guard deleted == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }

        for (position, block) in blocks.enumerated() {
            let insert = try prepare("""
            INSERT INTO blocks (note_id, position, content, content_hash, line_start, line_end)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_int64(insert, 1, noteID)
            sqlite3_bind_int(insert, 2, Int32(position))
            sqlite3_bind_text(insert, 3, block.markdown, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 4, ContentHasher.hash(block.markdown), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insert, 5, Int32(block.lineStart))
            sqlite3_bind_int(insert, 6, Int32(block.lineEnd))
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    /// Replaces all task rows for a note. Like `replaceBlocks`, reprojecting a note never
    /// appends, so the tasks table stays a rebuildable projection of the Markdown.
    public func replaceTasks(noteID: Int64, tasks: [TaskItem]) throws {
        let connection = try requireHandle()
        let delete = try prepare("DELETE FROM tasks WHERE note_id = ?;")
        sqlite3_bind_int64(delete, 1, noteID)
        let deleted = sqlite3_step(delete)
        sqlite3_finalize(delete)
        guard deleted == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }

        let indexedAt = Self.timestamp()
        for task in tasks {
            let insert = try prepare("""
            INSERT INTO tasks
                (note_id, source_key, line_number, title, status, tags, mentions, due, section_heading, original_line, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_int64(insert, 1, noteID)
            sqlite3_bind_text(insert, 2, task.sourceKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insert, 3, Int32(task.lineNumber))
            sqlite3_bind_text(insert, 4, task.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 5, task.status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 6, task.tags.joined(separator: " "), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 7, task.mentions.joined(separator: " "), -1, SQLITE_TRANSIENT)
            bindOptionalText(insert, 8, task.due?.token)
            bindOptionalText(insert, 9, task.sectionHeading)
            sqlite3_bind_text(insert, 10, task.originalLine, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 11, indexedAt, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    /// Open tasks across all notes, joined to their source note path and ordered by path then
    /// line. Completed tasks are excluded here so callers cannot accidentally surface them.
    public func openTasks() throws -> [TaskItem] {
        let statement = try prepare("""
        SELECT n.rel_path, t.line_number, t.title, t.status, t.tags, t.mentions, t.due, t.section_heading, t.original_line
        FROM tasks t
        JOIN notes n ON t.note_id = n.id
        WHERE t.status = 'open'
        ORDER BY n.rel_path, t.line_number;
        """)
        defer { sqlite3_finalize(statement) }

        var items: [TaskItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(TaskItem(
                title: columnText(statement, 2) ?? "",
                status: TaskItem.Status(rawValue: columnText(statement, 3) ?? "open") ?? .open,
                tags: Self.splitList(columnText(statement, 4)),
                mentions: Self.splitList(columnText(statement, 5)),
                due: columnText(statement, 6).flatMap(TaskItem.Due.init(token:)),
                notePath: columnText(statement, 0) ?? "",
                lineNumber: Int(sqlite3_column_int(statement, 1)),
                originalLine: columnText(statement, 8) ?? "",
                sectionHeading: columnText(statement, 7)
            ))
        }
        return items
    }

    public func taskCount() throws -> Int {
        try queryInts("SELECT COUNT(*) FROM tasks;").first ?? 0
    }

    /// Records that a source task was rolled into a target note. The Markdown marker remains
    /// the rebuildable dedup source; this row is an audit record and a fast store check.
    @discardableResult
    public func recordRollover(_ record: RolloverRecord) throws -> Bool {
        let connection = try requireHandle()
        let statement = try prepare("""
        INSERT OR IGNORE INTO rollovers
            (source_key, source_note_path, source_line_number, source_title, target_note_path, marker, rolled_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, record.sourceKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, record.sourceNotePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, Int32(record.sourceLineNumber))
        sqlite3_bind_text(statement, 4, record.sourceTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, record.targetNotePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, record.marker, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, Self.timestamp(), -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }
        return sqlite3_changes(connection) > 0
    }

    public func rolloverCount() throws -> Int {
        try queryInts("SELECT COUNT(*) FROM rollovers;").first ?? 0
    }

    public func noteCount() throws -> Int {
        try queryInts("SELECT COUNT(*) FROM notes;").first ?? 0
    }

    /// All indexed note paths, used to reconcile the projection against the files on disk
    /// (a rebuild prunes rows whose Markdown file no longer exists).
    public func noteRelativePaths() throws -> [String] {
        try queryStrings("SELECT rel_path FROM notes ORDER BY rel_path;")
    }

    public func blockCount() throws -> Int {
        try queryInts("SELECT COUNT(*) FROM blocks;").first ?? 0
    }

    public func note(relativePath: String) throws -> NoteRecord? {
        let statement = try prepare("""
        SELECT id, rel_path, title, content_hash, byte_count, modified_at, indexed_at
        FROM notes WHERE rel_path = ?;
        """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, relativePath, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return NoteRecord(
            id: sqlite3_column_int64(statement, 0),
            relativePath: columnText(statement, 1) ?? relativePath,
            title: columnText(statement, 2),
            contentHash: columnText(statement, 3) ?? "",
            byteCount: Int(sqlite3_column_int(statement, 4)),
            modifiedAt: columnText(statement, 5),
            indexedAt: columnText(statement, 6) ?? ""
        )
    }

    /// Removes a note, its blocks and tasks (via cascade), and its search row. Used when a
    /// Markdown file disappears from the workspace so the projection matches the files on
    /// disk. The note delete and the FTS delete run in one transaction so a failure cannot
    /// orphan a search row pointing at a deleted note.
    public func deleteNote(relativePath: String) throws {
        try withTransaction {
            try deleteRows(table: "notes", relativePath: relativePath)
            try deleteRows(table: "notes_fts", relativePath: relativePath)
        }
    }

    /// Deletes rows matching `rel_path` from a fixed, non-user-supplied table name.
    private func deleteRows(table: String, relativePath: String) throws {
        let connection = try requireHandle()
        let statement = try prepare("DELETE FROM \(table) WHERE rel_path = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, relativePath, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }
    }

    public func healthSummary() -> String {
        guard handle != nil else {
            return "Database at \(configuration.path) (not open)"
        }
        let notes = (try? noteCount()) ?? 0
        let blocks = (try? blockCount()) ?? 0
        return "Database at \(configuration.path): \(notes) notes, \(blocks) blocks"
    }

    // MARK: - SQLite helpers

    private func requireHandle() throws -> OpaquePointer {
        guard let handle else { throw StoreError.notOpen }
        return handle
    }

    /// Runs `body` inside a single SQLite transaction, committing on success and rolling
    /// back on any thrown error. Mirrors the control flow used by `migrate()`.
    private func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func exec(_ sql: String) throws {
        let connection = try requireHandle()
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "code \(result)"
            sqlite3_free(errorPointer)
            throw StoreError.sql(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let connection = try requireHandle()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(connection)))
        }
        return statement
    }

    private func queryInts(_ sql: String, text: String? = nil) throws -> [Int] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let text {
            sqlite3_bind_text(statement, 1, text, -1, SQLITE_TRANSIENT)
        }
        var values: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(Int(sqlite3_column_int64(statement, 0)))
        }
        return values
    }

    private func queryStrings(_ sql: String) throws -> [String] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = columnText(statement, 0) {
                values.append(text)
            }
        }
        return values
    }

    private func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    /// Reconstructs a space-joined token list (tags, mentions) stored in a single column.
    private static func splitList(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: " ").map(String.init)
    }

    private static func timestamp(from date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
