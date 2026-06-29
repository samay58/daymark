import XCTest
import DaymarkCore

final class DynamicBlockTests: XCTestCase {
    private func makeRoot() -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-dynamic-cache-\(UUID().uuidString)"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return WorkspaceRoot(path: path)
    }

    func testParserFindsOpenLoopsCommandWithTagArgument() throws {
        let commands = try DynamicBlockParser().parse(
            markdown: """
            # Today

              /daymark\topen-loops #deal/acme
            """,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].sourcePath, "daily/2026/06/2026-06-29.md")
        XCTAssertEqual(commands[0].lineNumber, 3)
        XCTAssertEqual(commands[0].rawText, "/daymark\topen-loops #deal/acme")
        XCTAssertEqual(commands[0].command, .openLoops)
        XCTAssertEqual(commands[0].arguments, ["#deal/acme"])
    }

    func testParserHandlesMultipleCommandsCRLFAndIgnoresFencedCode() throws {
        let markdown = """
        /daymark open-loops\r
        ```\r
        /daymark weekly-review\r
        ```\r
        /daymark weekly-review\r
        """

        let commands = try DynamicBlockParser().parse(markdown: markdown, sourcePath: "daily/today.md")

        XCTAssertEqual(commands.map(\.command), [.openLoops, .weeklyReview])
        XCTAssertEqual(commands.map(\.lineNumber), [1, 5])
        XCTAssertEqual(commands.map(\.ordinal), [1, 2])
    }

    func testParserRejectsUnsupportedCommandsWithLineContext() {
        XCTAssertThrowsError(try DynamicBlockParser().parse(
            markdown: "/daymark today-calendar\n",
            sourcePath: "daily/today.md"
        )) { error in
            XCTAssertEqual(
                (error as? DynamicBlockError)?.errorDescription,
                "unsupported dynamic block command on line 1: today-calendar"
            )
        }
    }

    func testOpenLoopsRendererUsesExistingGroupingAndTagFiltering() throws {
        let invocation = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark open-loops #deal/acme",
            command: .openLoops,
            arguments: ["#deal/acme"],
            ordinal: 1
        )
        let tasks = [
            TaskItem(title: "ship the memo #deal/acme due:today", status: .open, tags: ["#deal/acme"], due: .today, notePath: "daily/a.md", lineNumber: 3),
            TaskItem(title: "done task #deal/acme", status: .completed, tags: ["#deal/acme"], notePath: "daily/a.md", lineNumber: 4),
            TaskItem(title: "other project #deal/beta", status: .open, tags: ["#deal/beta"], notePath: "daily/b.md", lineNumber: 5)
        ]

        let rendered = try DynamicBlockRenderer().render(invocation: invocation, tasks: tasks, referenceDate: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(rendered.contains("### Open Loops"))
        XCTAssertTrue(rendered.contains("#### Due today"))
        XCTAssertTrue(rendered.contains("- [ ] ship the memo #deal/acme due:today  (daily/a.md:3)"))
        XCTAssertFalse(rendered.contains("done task"))
        XCTAssertFalse(rendered.contains("other project"))
    }

    func testPatchPlanInsertsGeneratedRegionAndThenReplacesItIdempotently() throws {
        let markdown = """
        Before
        /daymark open-loops
        After
        """
        let tasks = [
            TaskItem(title: "follow up", status: .open, notePath: "daily/a.md", lineNumber: 7)
        ]

        let firstPlan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: tasks,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(firstPlan.patches.count, 1)
        XCTAssertEqual(firstPlan.patches[0].operation, .insert)
        XCTAssertEqual(firstPlan.patches[0].commandLine, 2)

        let firstApplied = try firstPlan.apply(to: markdown)
        XCTAssertTrue(firstApplied.contains("/daymark open-loops"))
        XCTAssertTrue(firstApplied.contains("<!-- daymark:block-begin "))
        XCTAssertTrue(firstApplied.contains("- [ ] follow up  (daily/a.md:7)"))
        XCTAssertTrue(firstApplied.contains("Before"))
        XCTAssertTrue(firstApplied.contains("After"))

        let secondPlan = try DynamicBlockPatchPlanner().plan(
            markdown: firstApplied,
            sourcePath: "daily/today.md",
            tasks: tasks,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(secondPlan.patches[0].operation, .replacement)
        XCTAssertEqual(try secondPlan.apply(to: firstApplied), firstApplied)
    }

    func testPatchPlanPreservesUserTextAroundExistingGeneratedRegion() throws {
        let markdown = """
        Intro
        /daymark open-loops
        <!-- daymark:block-begin 95dfab41c9b5 -->
        stale
        <!-- daymark:block-end 95dfab41c9b5 -->
        Outro
        """
        let tasks = [
            TaskItem(title: "fresh task", status: .open, notePath: "daily/source.md", lineNumber: 2)
        ]

        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: tasks,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        let applied = try plan.apply(to: markdown)

        XCTAssertTrue(applied.hasPrefix("Intro\n/daymark open-loops\n"))
        XCTAssertTrue(applied.hasSuffix("Outro"))
        XCTAssertFalse(applied.contains("stale"))
        XCTAssertTrue(applied.contains("fresh task"))
    }

    func testGeneratedRegionsCanBeStrippedBeforeTaskParsing() {
        let markdown = """
        - [ ] real task
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        - [ ] generated task
        <!-- daymark:block-end abc123 -->
        After
        """

        let stripped = DynamicBlockRegion.removingGeneratedRegions(from: markdown)

        XCTAssertTrue(stripped.contains("- [ ] real task"))
        XCTAssertTrue(stripped.contains("/daymark open-loops"))
        XCTAssertFalse(stripped.contains("generated task"))
        XCTAssertTrue(stripped.contains("After"))
    }

    func testCacheRecordsRenderedMetadataAndUpdatesExistingRecord() throws {
        let root = makeRoot()
        let markdown = "/daymark open-loops\n"
        let sourcePath = "daily/today.md"
        let firstTask = TaskItem(title: "first task", status: .open, notePath: "daily/a.md", lineNumber: 1)
        let firstPlan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: sourcePath,
            tasks: [firstTask],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        let refreshedAt = Date(timeIntervalSince1970: 0)
        let store = DynamicBlockCacheStore()

        try store.record(patches: firstPlan.patches, root: root, refreshedAt: refreshedAt)

        let firstRecords = try store.read(root: root)
        XCTAssertEqual(firstRecords.count, 1)
        XCTAssertEqual(firstRecords[0].sourcePath, sourcePath)
        XCTAssertEqual(firstRecords[0].commandHash, firstPlan.patches[0].commandHash)
        XCTAssertEqual(firstRecords[0].rawCommand, "/daymark open-loops")
        XCTAssertEqual(firstRecords[0].rendererName, "open-loops")
        XCTAssertEqual(firstRecords[0].renderedOutputHash, ContentHasher.hash(firstPlan.patches[0].generatedMarkdown))
        XCTAssertEqual(firstRecords[0].refreshedAt, "1970-01-01T00:00:00Z")

        let secondTask = TaskItem(title: "second task", status: .open, notePath: "daily/b.md", lineNumber: 2)
        let secondPlan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: sourcePath,
            tasks: [secondTask],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        try store.record(patches: secondPlan.patches, root: root, refreshedAt: Date(timeIntervalSince1970: 60))

        let updatedRecords = try store.read(root: root)
        XCTAssertEqual(updatedRecords.count, 1)
        XCTAssertEqual(updatedRecords[0].renderedOutputHash, ContentHasher.hash(secondPlan.patches[0].generatedMarkdown))
        XCTAssertEqual(updatedRecords[0].refreshedAt, "1970-01-01T00:01:00Z")
    }

    func testCacheRecordOverwritesInvalidRebuildableMetadata() throws {
        let root = makeRoot()
        let cacheURL = root.expandedURL
            .appendingPathComponent(".daymark", isDirectory: true)
            .appendingPathComponent("dynamic-blocks.json")
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: cacheURL, atomically: true, encoding: .utf8)

        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: "/daymark open-loops\n",
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "fresh task", status: .open, notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )

        try DynamicBlockCacheStore().record(
            patches: plan.patches,
            root: root,
            refreshedAt: Date(timeIntervalSince1970: 0)
        )

        let records = try DynamicBlockCacheStore().read(root: root)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].rawCommand, "/daymark open-loops")
    }
}
