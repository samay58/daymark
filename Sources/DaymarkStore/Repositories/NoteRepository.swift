import Foundation
import DaymarkCore

/// Ergonomic projection facade over `Database`. Projects a Markdown note into its
/// note row and block rows as one logical operation, and exposes local search.
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
        blocks: [Block]
    ) async throws {
        let id = try await database.upsertNote(
            relativePath: relativePath,
            title: title,
            content: content,
            modifiedAt: modifiedAt
        )
        try await database.replaceBlocks(noteID: id, blocks: blocks)
    }

    public func removeNote(relativePath: String) async throws {
        try await database.deleteNote(relativePath: relativePath)
    }

    public func search(_ query: String, limit: Int = 20) async throws -> [SearchHit] {
        try await database.search(query, limit: limit)
    }
}
