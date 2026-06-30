import XCTest
import DaymarkCore
import DaymarkStore
@testable import DaymarkIndexer

final class DailyMarkdownProjectionReaderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }

    private func makeBootstrappedWorkspace() throws -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-reader-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let root = WorkspaceRoot(path: path)
        _ = try WorkspaceBootstrapper().bootstrap(root: root)
        return root
    }

    private func write(_ markdown: String, relativePath: String, root: WorkspaceRoot) throws {
        try AtomicFileWriter().write(markdown, to: root.expandedURL.appendingPathComponent(relativePath))
    }

    func testAllTasksStripsGeneratedRegions() throws {
        let root = try makeBootstrappedWorkspace()
        try write("""
        # Today

        - [ ] real task
        <!-- daymark:block-begin abc -->
        - [ ] generated task
        <!-- daymark:block-end abc -->
        """, relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let tasks = try DailyMarkdownProjectionReader(root: root).allTasks()
        XCTAssertEqual(tasks.map(\.title), ["real task"])
    }

    func testReaderOpenTasksMatchDatabaseProjectionAfterRebuild() async throws {
        let root = try makeBootstrappedWorkspace()
        try write("# A\n\n- [ ] a1\n- [x] done\n", relativePath: "daily/2026/06/2026-06-27.md", root: root)
        try write("# B\n\n- [ ] b1\n", relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let dbPath = root.expandedURL.appendingPathComponent(".daymark/daymark.db").path
        let db = Database(configuration: DatabaseConfiguration(path: dbPath))
        try await db.open()
        _ = try await db.migrate()
        _ = try await WorkspaceIndexer(root: root, database: db, calendar: calendar).rebuild()

        let dbOpen = try await db.openTasks().map { "\($0.notePath):\($0.lineNumber):\($0.title)" }
        let readerOpen = try DailyMarkdownProjectionReader(root: root).allTasks()
            .filter { $0.status == .open }
            .map { "\($0.notePath):\($0.lineNumber):\($0.title)" }

        XCTAssertEqual(readerOpen, dbOpen, "the Markdown reader and the SQLite projection must agree")
        await db.close()
    }

    func testAllSourcesListsTaggedMarkdownOutsideGeneratedRegionsAndCommandLines() throws {
        let root = try makeBootstrappedWorkspace()
        try write("""
        # Today

        /daymark source-list #project/daymark
        <!-- daymark:block-begin abc -->
        - Generated #project/daymark
        <!-- daymark:block-end abc -->
        """, relativePath: "daily/2026/06/2026-06-29.md", root: root)
        try write("""
        # Daymark Project

        Build the dynamic block renderer. #project/daymark
        """, relativePath: "projects/daymark.md", root: root)
        try write("""
        # Other Project

        Different work. #project/other
        """, relativePath: "projects/other.md", root: root)

        let sources = try DailyMarkdownProjectionReader(root: root).allSources()

        XCTAssertEqual(
            sources.filter { $0.tags.contains("#project/daymark") }.map(\.relativePath),
            ["projects/daymark.md"]
        )
        XCTAssertEqual(
            sources.first { $0.relativePath == "projects/daymark.md" }?.title,
            "Daymark Project"
        )
    }

    func testAllCodexContextsMatchesArtifactsByTagAndTaggedSourcePath() throws {
        let root = try makeBootstrappedWorkspace()
        try write("""
        # Daymark Project

        Build dynamic handoff blocks. #project/daymark
        """, relativePath: "projects/daymark.md", root: root)
        try write("""
        # Ship beta handoff

        ## Goal

        Finish the local renderer.

        ## Source

        Path: `projects/daymark.md`
        """, relativePath: "specs/tasks/2026-06-29-ship-beta.md", root: root)
        try write("""
        # Direct tag handoff

        This task is tagged #project/daymark.
        """, relativePath: "specs/tasks/2026-06-29-direct.md", root: root)
        try write("""
        # Generated-only task

        <!-- daymark:block-begin abc -->
        #project/daymark
        <!-- daymark:block-end abc -->
        """, relativePath: "specs/tasks/2026-06-29-generated.md", root: root)
        try write("""
        # Context Bundle: Ship beta handoff

        ## Task

        Task: `specs/tasks/2026-06-29-ship-beta.md`
        """, relativePath: "artifacts/context-bundles/2026-06-29-ship-beta-context.md", root: root)

        let contexts = try DailyMarkdownProjectionReader(root: root).allCodexContexts()
        let daymark = contexts.filter { $0.tags.contains("#project/daymark") }

        XCTAssertEqual(daymark.map(\.relativePath), [
            "artifacts/context-bundles/2026-06-29-ship-beta-context.md",
            "specs/tasks/2026-06-29-direct.md",
            "specs/tasks/2026-06-29-ship-beta.md"
        ])
        XCTAssertEqual(
            daymark.first { $0.relativePath == "specs/tasks/2026-06-29-ship-beta.md" }?.sourcePaths,
            ["projects/daymark.md"]
        )
        XCTAssertEqual(
            daymark.first { $0.relativePath == "artifacts/context-bundles/2026-06-29-ship-beta-context.md" }?.taskPaths,
            ["specs/tasks/2026-06-29-ship-beta.md"]
        )
        XCTAssertFalse(daymark.map(\.relativePath).contains("specs/tasks/2026-06-29-generated.md"))
    }
}
