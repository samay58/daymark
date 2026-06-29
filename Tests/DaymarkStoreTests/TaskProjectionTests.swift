import XCTest
import DaymarkCore
@testable import DaymarkStore

final class TaskProjectionTests: XCTestCase {
    private func makeMigratedRepository() async throws -> NoteRepository {
        let path = "\(NSTemporaryDirectory())daymark-tasks-\(UUID().uuidString)/daymark.db"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        let db = Database(configuration: DatabaseConfiguration(path: path))
        try await db.open()
        _ = try await db.migrate()
        return NoteRepository(database: db)
    }

    private let path = "daily/2026/06/2026-06-28.md"

    func testTasksTableExistsAfterMigrate() async throws {
        let repo = try await makeMigratedRepository()
        let tables = try await repo.database.tableNames()
        XCTAssertTrue(tables.contains("tasks"))
    }

    func testProjectsOnlyOpenTasksIntoOpenTasksQuery() async throws {
        let repo = try await makeMigratedRepository()
        let content = """
        ## Capture

        - [ ] open one @sarah
        - [x] done one
        """
        let tasks = TaskParser().parse(markdown: content, notePath: path)
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)

        let open = try await repo.database.openTasks()
        XCTAssertEqual(open.count, 1, "completed tasks are excluded from openTasks")
        XCTAssertEqual(open[0].title, "open one @sarah")
        XCTAssertEqual(open[0].notePath, path)
    }

    func testReprojectingReplacesTasksWithoutDuplicating() async throws {
        let repo = try await makeMigratedRepository()
        let content = """
        - [ ] one
        - [ ] two
        """
        let tasks = TaskParser().parse(markdown: content, notePath: path)
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)

        let open = try await repo.database.openTasks()
        XCTAssertEqual(open.count, 2, "reprojection replaces task rows, it does not append")
    }

    func testRebuildIsDeterministic() async throws {
        let repo = try await makeMigratedRepository()
        let content = "- [ ] alpha\n- [ ] beta"
        let tasks = TaskParser().parse(markdown: content, notePath: path)

        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)
        let first = try await repo.database.openTasks()
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)
        let second = try await repo.database.openTasks()

        XCTAssertEqual(first, second, "the same Markdown must project to the same tasks")
    }

    func testDeletingNoteRemovesItsTasks() async throws {
        let repo = try await makeMigratedRepository()
        let content = "- [ ] gone soon"
        let tasks = TaskParser().parse(markdown: content, notePath: path)
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)

        try await repo.removeNote(relativePath: path)
        let open = try await repo.database.openTasks()
        XCTAssertTrue(open.isEmpty, "removing a note removes its tasks")
    }

    func testRoundTripsTaskMetadata() async throws {
        let repo = try await makeMigratedRepository()
        let content = """
        ## Capture

        - [ ] Send memo #deal/acme @sarah due:2026-06-29
        """
        let tasks = TaskParser().parse(markdown: content, notePath: path)
        try await repo.projectNote(relativePath: path, title: nil, content: content, modifiedAt: nil, blocks: [], tasks: tasks)

        let open = try await repo.database.openTasks()
        XCTAssertEqual(open.count, 1)
        let task = open[0]
        XCTAssertEqual(task.tags, ["#deal/acme"])
        XCTAssertEqual(task.mentions, ["@sarah"])
        XCTAssertEqual(task.due, .date("2026-06-29"))
        XCTAssertEqual(task.sectionHeading, "Capture")
        XCTAssertEqual(task.lineNumber, 3)
        XCTAssertEqual(task.originalLine, "- [ ] Send memo #deal/acme @sarah due:2026-06-29")
    }

    func testOpenTasksSpanMultipleNotesOrderedByPath() async throws {
        let repo = try await makeMigratedRepository()
        let yesterday = "daily/2026/06/2026-06-27.md"
        let yContent = "- [ ] yesterday task"
        let tContent = "- [ ] today task"
        try await repo.projectNote(relativePath: yesterday, title: nil, content: yContent, modifiedAt: nil, blocks: [], tasks: TaskParser().parse(markdown: yContent, notePath: yesterday))
        try await repo.projectNote(relativePath: path, title: nil, content: tContent, modifiedAt: nil, blocks: [], tasks: TaskParser().parse(markdown: tContent, notePath: path))

        let open = try await repo.database.openTasks()
        XCTAssertEqual(open.map(\.notePath), [yesterday, path], "open tasks are ordered by note path then line")
    }
}
