import Foundation
import DaymarkCore

/// Ergonomic projection facade over `Database`. Projects a Markdown note into its note
/// row, search index, blocks, and tasks as one atomic operation, and exposes local search.
/// The multi-table consistency boundary lives in `Database.replaceNoteProjection`, not here.
public struct NoteRepository {
    public let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func projectNote(
        relativePath: String,
        title: String?,
        content: String,
        modifiedAt: Date?,
        blocks: [Block],
        tasks: [TaskItem] = []
    ) async throws {
        try await database.replaceNoteProjection(
            relativePath: relativePath,
            title: title,
            content: content,
            modifiedAt: modifiedAt,
            blocks: blocks,
            tasks: tasks
        )
    }

    public func removeNote(relativePath: String) async throws {
        try await database.deleteNote(relativePath: relativePath)
    }

    public func search(_ query: String, limit: Int = 20) async throws -> [SearchHit] {
        try await database.search(query, limit: limit)
    }
}
