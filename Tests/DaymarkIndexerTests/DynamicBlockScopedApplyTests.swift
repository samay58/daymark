import XCTest
import DaymarkCore
import DaymarkIndexer

/// The app approves dynamic blocks one surface at a time: a card applies only its own patch, and
/// the new-block popover applies only the inserts it showed. Both narrow a preview's plan to a
/// subset of its patches. These tests pin down that a subset applies correctly against the same
/// source Markdown and writes nothing it was not given.
final class DynamicBlockScopedApplyTests: XCTestCase {
    private let sourcePath = "daily/2026/06/2026-06-29.md"
    private let yesterdayPath = "daily/2026/06/2026-06-28.md"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private var referenceDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 29
        return calendar.date(from: components) ?? Date()
    }

    private func makeRoot() -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-scoped-apply-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return WorkspaceRoot(path: path)
    }

    private func write(_ markdown: String, relativePath: String, root: WorkspaceRoot) throws {
        let url = root.expandedURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func preview(_ markdown: String, root: WorkspaceRoot) throws -> DynamicBlockRefreshPreview {
        try DynamicBlockRefreshService().preview(
            markdown: markdown,
            sourcePath: sourcePath,
            root: root,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private func regionCount(_ markdown: String) -> Int {
        markdown.components(separatedBy: "daymark:block-begin").count - 1
    }

    /// A note with one existing open-loops region (now out of date) and a new command above it,
    /// so the insert shifts every line below it.
    private func makeMixedPlan(root: WorkspaceRoot) throws -> (markdown: String, seeded: String, preview: DynamicBlockRefreshPreview) {
        try write("- [ ] first task\n", relativePath: yesterdayPath, root: root)
        let seed = "Intro\n/daymark open-loops\nOutro\n"
        try write(seed, relativePath: sourcePath, root: root)
        let seeded = try DynamicBlockRefreshService()
            .apply(preview: preview(seed, root: root), currentMarkdown: seed, root: root)
            .updatedMarkdown

        try write("- [ ] first task\n- [ ] second task\n", relativePath: yesterdayPath, root: root)
        let markdown = "/daymark open-loops #project/new\n" + seeded
        try write(markdown, relativePath: sourcePath, root: root)
        return (markdown, seeded, try preview(markdown, root: root))
    }

    func testReplacementAloneLeavesNewCommandWithoutARegion() throws {
        let root = makeRoot()
        let (markdown, _, full) = try makeMixedPlan(root: root)
        let replacement = try XCTUnwrap(full.plan.patches.first { $0.operation == .replacement })
        let insert = try XCTUnwrap(full.plan.patches.first { $0.operation == .insert })

        var scoped = full
        scoped.plan.patches = [replacement]
        let result = try DynamicBlockRefreshService().apply(preview: scoped, currentMarkdown: markdown, root: root)

        XCTAssertEqual(regionCount(result.updatedMarkdown), 1)
        XCTAssertTrue(result.updatedMarkdown.hasPrefix("/daymark open-loops #project/new\nIntro\n/daymark open-loops\n<!-- daymark:block-begin"))
        XCTAssertTrue(result.updatedMarkdown.contains("second task"))
        XCTAssertTrue(result.updatedMarkdown.hasSuffix("Outro\n"))

        let cached = Set(try DynamicBlockCacheStore().read(root: root).map(\.commandHash))
        XCTAssertTrue(cached.contains(replacement.commandHash))
        XCTAssertFalse(cached.contains(insert.commandHash))
    }

    func testInsertsAloneLeaveExistingRegionUntouched() throws {
        let root = makeRoot()
        let (markdown, seeded, full) = try makeMixedPlan(root: root)
        let insert = try XCTUnwrap(full.plan.patches.first { $0.operation == .insert })

        var scoped = full
        scoped.plan.patches = [insert]
        let result = try DynamicBlockRefreshService().apply(preview: scoped, currentMarkdown: markdown, root: root)

        XCTAssertEqual(regionCount(result.updatedMarkdown), 2)
        XCTAssertTrue(result.updatedMarkdown.hasPrefix("/daymark open-loops #project/new\n<!-- daymark:block-begin \(insert.commandHash) -->"))
        XCTAssertTrue(result.updatedMarkdown.hasSuffix(seeded), "the out-of-date region must not be rewritten")
        XCTAssertFalse(result.updatedMarkdown.contains("second task"))
    }

    func testEmptyScopeWritesTheNoteUnchanged() throws {
        let root = makeRoot()
        let (markdown, _, full) = try makeMixedPlan(root: root)

        var scoped = full
        scoped.plan.patches = []
        let result = try DynamicBlockRefreshService().apply(preview: scoped, currentMarkdown: markdown, root: root)

        XCTAssertEqual(result.updatedMarkdown, markdown)
    }
}
