import XCTest
import DaymarkCore
@testable import DaymarkStore

final class NoteProjectionTests: XCTestCase {
    private func makeMigratedRepository() async throws -> NoteRepository {
        let path = "\(NSTemporaryDirectory())daymark-proj-\(UUID().uuidString)/daymark.db"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        let db = Database(configuration: DatabaseConfiguration(path: path))
        try await db.open()
        _ = try await db.migrate()
        return NoteRepository(database: db)
    }

    func testProjectNoteInsertsNoteAndBlocks() async throws {
        let repo = try await makeMigratedRepository()
        let blocks = [
            Block(id: "line_1", markdown: "# Today", lineStart: 1, lineEnd: 1),
            Block(id: "line_2", markdown: "Body", lineStart: 2, lineEnd: 2)
        ]
        try await repo.projectNote(relativePath: "daily/2026/06/2026-06-28.md", title: "Today", content: "# Today\nBody", modifiedAt: nil, blocks: blocks)

        let noteCount = try await repo.database.noteCount()
        let blockCount = try await repo.database.blockCount()
        XCTAssertEqual(noteCount, 1)
        XCTAssertEqual(blockCount, 2)
    }

    func testProjectingSamePathUpdatesInsteadOfDuplicating() async throws {
        let repo = try await makeMigratedRepository()
        let path = "daily/2026/06/2026-06-28.md"
        try await repo.projectNote(relativePath: path, title: "v1", content: "one", modifiedAt: nil, blocks: [Block(id: "l1", markdown: "one", lineStart: 1, lineEnd: 1)])
        try await repo.projectNote(relativePath: path, title: "v2", content: "two", modifiedAt: nil, blocks: [Block(id: "l1", markdown: "two", lineStart: 1, lineEnd: 1)])

        let noteCount = try await repo.database.noteCount()
        XCTAssertEqual(noteCount, 1, "same rel path must upsert, not duplicate")

        let record = try await repo.database.note(relativePath: path)
        XCTAssertEqual(record?.title, "v2")
        XCTAssertEqual(record?.contentHash, ContentHasher.hash("two"))
    }

    func testReplaceBlocksDoesNotAppend() async throws {
        let repo = try await makeMigratedRepository()
        let path = "daily/2026/06/2026-06-28.md"
        try await repo.projectNote(relativePath: path, title: "a", content: "x", modifiedAt: nil, blocks: [
            Block(id: "l1", markdown: "a", lineStart: 1, lineEnd: 1),
            Block(id: "l2", markdown: "b", lineStart: 2, lineEnd: 2),
            Block(id: "l3", markdown: "c", lineStart: 3, lineEnd: 3)
        ])
        try await repo.projectNote(relativePath: path, title: "a", content: "x", modifiedAt: nil, blocks: [
            Block(id: "l1", markdown: "a", lineStart: 1, lineEnd: 1)
        ])

        let blockCount = try await repo.database.blockCount()
        XCTAssertEqual(blockCount, 1, "reprojecting should replace blocks, not append")
    }
}
