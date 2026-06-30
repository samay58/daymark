import Foundation
import DaymarkCore
import DaymarkStore

/// Projects Markdown daily notes into the SQLite index. The projection is a pure
/// function of the files on disk: indexing is idempotent and the database can be
/// rebuilt from the Markdown at any time. Markdown remains the source of truth.
public struct WorkspaceIndexer {
    public let root: WorkspaceRoot
    public let database: Database
    public let calendar: Calendar
    private let reader: DailyMarkdownProjectionReader

    public init(root: WorkspaceRoot, database: Database, calendar: Calendar = .current) {
        self.root = root
        self.database = database
        self.calendar = calendar
        self.reader = DailyMarkdownProjectionReader(root: root)
    }

    /// Reads a workspace-relative Markdown file, parses it into blocks and tasks, and upserts
    /// the projection. Returns false when the file does not exist. Never appends on reindex.
    @discardableResult
    public func indexFile(relativePath: String, fileManager: FileManager = .default) async throws -> Bool {
        guard let projection = try reader.projection(relativePath: relativePath, fileManager: fileManager) else {
            return false
        }
        let repository = NoteRepository(database: database)
        try await repository.projectNote(
            relativePath: projection.relativePath,
            title: projection.title,
            content: projection.content,
            modifiedAt: projection.modifiedAt,
            blocks: projection.blocks,
            tasks: projection.tasks
        )
        return true
    }

    /// Indexes today's daily note.
    public func indexToday(date: Date = Date(), fileManager: FileManager = .default) async throws {
        let relativePath = DailyNote.relativePath(for: date, calendar: calendar)
        _ = try await indexFile(relativePath: relativePath, fileManager: fileManager)
    }

    /// Reprojects every daily Markdown file under `daily/` and prunes index rows whose
    /// Markdown file no longer exists, so the projection matches the files on disk. Returns
    /// the number of files indexed. Safe to run against a fresh database.
    @discardableResult
    public func rebuild(fileManager: FileManager = .default) async throws -> Int {
        let onDisk = reader.dailyRelativePaths(fileManager: fileManager)
        var indexed = 0
        for relativePath in onDisk {
            if try await indexFile(relativePath: relativePath, fileManager: fileManager) {
                indexed += 1
            }
        }

        // Reconcile: drop projections for daily notes deleted from disk so stale tasks
        // (and search rows) cannot resurface. The on-disk set and the stored rel_paths
        // share one relative-path computation (the reader), so the keys match exactly.
        let onDiskSet = Set(onDisk)
        let repository = NoteRepository(database: database)
        for indexedPath in try await database.noteRelativePaths()
        where indexedPath.hasPrefix("daily/") && !onDiskSet.contains(indexedPath) {
            try await repository.removeNote(relativePath: indexedPath)
        }
        return indexed
    }
}
