import XCTest
import DaymarkCore
import DaymarkIndexer

final class DynamicBlockRefreshServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func makeRoot() -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-refresh-service-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return WorkspaceRoot(path: path)
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func write(_ markdown: String, relativePath: String, root: WorkspaceRoot) throws {
        let url = root.expandedURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relativePath: String, root: WorkspaceRoot) throws -> String {
        try String(contentsOf: root.expandedURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testPreviewPlansFromCurrentMarkdownAndWritesNothing() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        let markdown = """
        Intro stays.
        /daymark open-loops #project/daymark
        Outro stays.
        """
        try write(markdown, relativePath: sourcePath, root: root)
        try write("""
        # Yesterday

        - [ ] ship refresh #project/daymark due:2026-06-29
        """, relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let preview = try DynamicBlockRefreshService().preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )

        XCTAssertEqual(preview.plan.targetFilePath, sourcePath)
        XCTAssertEqual(preview.plan.patches.count, 1)
        XCTAssertEqual(preview.plan.patches[0].operation, .insert)
        XCTAssertTrue(preview.plan.patches[0].generatedMarkdown.contains("ship refresh #project/daymark"))
        XCTAssertEqual(try read(sourcePath, root: root), markdown)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.expandedURL.appendingPathComponent(".daymark").path))
    }

    func testPreviewUsesCurrentMarkdownTasksBeforeAutosave() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        try write("""
        # Today

        /daymark open-loops
        """, relativePath: sourcePath, root: root)
        let unsavedMarkdown = """
        # Today

        - [ ] unsaved task in editor

        /daymark open-loops
        """

        let preview = try DynamicBlockRefreshService().preview(
            markdown: unsavedMarkdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )

        XCTAssertTrue(preview.plan.patches[0].generatedMarkdown.contains("unsaved task in editor"))
        XCTAssertFalse((try read(sourcePath, root: root)).contains("unsaved task in editor"))
    }

    func testApplyWritesApprovedPreviewAndRecordsCache() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        let markdown = """
        Before.
        /daymark open-loops
        After.
        """
        try write(markdown, relativePath: sourcePath, root: root)
        try write("""
        # Yesterday

        - [ ] follow up
        """, relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let service = DynamicBlockRefreshService()
        let preview = try service.preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        let result = try service.apply(preview: preview, currentMarkdown: markdown, root: root)

        XCTAssertNil(result.cacheWarning)
        XCTAssertEqual(try read(sourcePath, root: root), result.updatedMarkdown)
        XCTAssertTrue(result.updatedMarkdown.contains("Before."))
        XCTAssertTrue(result.updatedMarkdown.contains("/daymark open-loops"))
        XCTAssertTrue(result.updatedMarkdown.contains("- [ ] follow up"))
        XCTAssertTrue(result.updatedMarkdown.contains("After."))
        XCTAssertEqual(result.updatedMarkdown.components(separatedBy: "daymark:block-begin").count - 1, 1)
        let cache = try read(".daymark/dynamic-blocks.json", root: root)
        XCTAssertTrue(cache.contains("\"rendererName\" : \"open-loops\""), cache)
    }

    func testApplyRefusesStalePreviewAndLeavesNoteUntouched() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        let markdown = "Intro\n/daymark open-loops\n"
        try write(markdown, relativePath: sourcePath, root: root)

        let service = DynamicBlockRefreshService()
        let preview = try service.preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        XCTAssertThrowsError(try service.apply(
            preview: preview,
            currentMarkdown: markdown + "new local edit\n",
            root: root
        )) { error in
            XCTAssertEqual(error as? DynamicBlockRefreshError, .stalePreview)
        }
        XCTAssertEqual(try read(sourcePath, root: root), markdown)
    }

    func testRepeatApplyReplacesExistingRegionWithoutDuplicating() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        let markdown = "Intro\n/daymark open-loops\nOutro\n"
        try write(markdown, relativePath: sourcePath, root: root)
        try write("- [ ] first task\n", relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let service = DynamicBlockRefreshService()
        let firstPreview = try service.preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        let first = try service.apply(preview: firstPreview, currentMarkdown: markdown, root: root)
        try write("""
        - [ ] first task
        - [ ] second task
        """, relativePath: "daily/2026/06/2026-06-28.md", root: root)

        let secondPreview = try service.preview(
            markdown: first.updatedMarkdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        XCTAssertEqual(secondPreview.plan.patches.first?.operation, .replacement)
        let second = try service.apply(preview: secondPreview, currentMarkdown: first.updatedMarkdown, root: root)

        XCTAssertEqual(second.updatedMarkdown.components(separatedBy: "daymark:block-begin").count - 1, 1)
        XCTAssertEqual(second.updatedMarkdown.components(separatedBy: "first task").count - 1, 1)
        XCTAssertEqual(second.updatedMarkdown.components(separatedBy: "second task").count - 1, 1)
        XCTAssertTrue(second.updatedMarkdown.contains("Intro"))
        XCTAssertTrue(second.updatedMarkdown.contains("Outro"))
    }

    func testCacheFailureReturnsWarningAfterNoteWrite() throws {
        let root = makeRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        let markdown = "/daymark open-loops\n"
        try write(markdown, relativePath: sourcePath, root: root)
        try write("- [ ] cached later\n", relativePath: "daily/2026/06/2026-06-28.md", root: root)
        try "not a directory".write(
            to: root.expandedURL.appendingPathComponent(".daymark"),
            atomically: true,
            encoding: .utf8
        )

        let service = DynamicBlockRefreshService()
        let preview = try service.preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        let result = try service.apply(preview: preview, currentMarkdown: markdown, root: root)

        XCTAssertNotNil(result.cacheWarning)
        XCTAssertEqual(try read(sourcePath, root: root), result.updatedMarkdown)
        XCTAssertTrue(result.updatedMarkdown.contains("cached later"))
    }
}
