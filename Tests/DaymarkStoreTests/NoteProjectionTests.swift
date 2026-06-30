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

    func testReprojectionReplacesTasksThroughTransactionalPath() async throws {
        let repo = try await makeMigratedRepository()
        let path = "daily/2026/06/2026-06-28.md"
        try await repo.projectNote(
            relativePath: path, title: "v1", content: "a", modifiedAt: nil,
            blocks: [Block(id: "l1", markdown: "a", lineStart: 1, lineEnd: 1)],
            tasks: [
                TaskItem(title: "first", status: .open, notePath: path, lineNumber: 1),
                TaskItem(title: "second", status: .open, notePath: path, lineNumber: 2)
            ]
        )
        try await repo.projectNote(
            relativePath: path, title: "v2", content: "b", modifiedAt: nil,
            blocks: [Block(id: "l1", markdown: "b", lineStart: 1, lineEnd: 1)],
            tasks: [TaskItem(title: "only", status: .open, notePath: path, lineNumber: 1)]
        )
        let noteCount = try await repo.database.noteCount()
        XCTAssertEqual(noteCount, 1)
        let taskCount = try await repo.database.taskCount()
        XCTAssertEqual(taskCount, 1, "reprojection replaces tasks, never appends")
        let openTitles = try await repo.database.openTasks().map(\.title)
        XCTAssertEqual(openTitles, ["only"])
    }

    func testDeleteNoteRemovesNoteBlocksTasksAndSearchRow() async throws {
        let repo = try await makeMigratedRepository()
        let path = "daily/2026/06/2026-06-28.md"
        try await repo.projectNote(
            relativePath: path, title: "Today", content: "# Today\n- [ ] open task", modifiedAt: nil,
            blocks: [Block(id: "l1", markdown: "# Today", lineStart: 1, lineEnd: 1)],
            tasks: [TaskItem(title: "open task", status: .open, notePath: path, lineNumber: 2)]
        )
        let beforeNotes = try await repo.database.noteCount()
        XCTAssertEqual(beforeNotes, 1)
        let beforeTasks = try await repo.database.taskCount()
        XCTAssertEqual(beforeTasks, 1)
        let beforeSearch = try await repo.search("Today")
        XCTAssertFalse(beforeSearch.isEmpty)

        try await repo.removeNote(relativePath: path)

        let afterNotes = try await repo.database.noteCount()
        XCTAssertEqual(afterNotes, 0)
        let afterBlocks = try await repo.database.blockCount()
        XCTAssertEqual(afterBlocks, 0, "blocks cascade-delete with the note")
        let afterTasks = try await repo.database.taskCount()
        XCTAssertEqual(afterTasks, 0, "tasks cascade-delete with the note")
        let afterSearch = try await repo.search("Today")
        XCTAssertTrue(afterSearch.isEmpty, "the FTS row is removed in the same transaction")
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
