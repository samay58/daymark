import XCTest
import DaymarkCore

final class DynamicBlockTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func makeRoot() -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-dynamic-cache-\(UUID().uuidString)"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return WorkspaceRoot(path: path)
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
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

    func testSourceListRendererListsMatchingSourcesInPathOrder() throws {
        let invocation = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark source-list #project/daymark",
            command: .sourceList,
            arguments: ["#project/daymark"],
            ordinal: 1
        )
        let sources = [
            DynamicBlockSource(title: "Beta", relativePath: "projects/beta.md", tags: ["#project/beta"]),
            DynamicBlockSource(title: "Today", relativePath: "daily/2026/06/2026-06-29.md", tags: ["#project/daymark"]),
            DynamicBlockSource(title: "Daymark", relativePath: "projects/daymark.md", tags: ["#project/daymark"])
        ]

        let rendered = try DynamicBlockRenderer().render(
            invocation: invocation,
            tasks: [],
            sources: sources,
            referenceDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(rendered.contains("### Source List: #project/daymark"))
        let todayRange = try XCTUnwrap(rendered.range(of: "- Today (`daily/2026/06/2026-06-29.md`)"))
        let projectRange = try XCTUnwrap(rendered.range(of: "- Daymark (`projects/daymark.md`)"))
        XCTAssertLessThan(todayRange.lowerBound, projectRange.lowerBound)
        XCTAssertFalse(rendered.contains("Beta"))
    }

    func testSourceListRendererRejectsMalformedArgumentsAndShowsPlainEmptyState() throws {
        let renderer = DynamicBlockRenderer()
        let missingArgument = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark source-list",
            command: .sourceList,
            ordinal: 1
        )
        let empty = try renderer.render(
            invocation: missingArgument,
            tasks: [],
            sources: [],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(empty, "### Source List\n\nAdd a tag argument, for example `#project/daymark`.\n")

        let malformed = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark source-list project/daymark",
            command: .sourceList,
            arguments: ["project/daymark"],
            ordinal: 1
        )
        XCTAssertThrowsError(try renderer.render(
            invocation: malformed,
            tasks: [],
            sources: [],
            referenceDate: Date(timeIntervalSince1970: 0)
        )) { error in
            XCTAssertEqual(
                (error as? DynamicBlockError)?.errorDescription,
                "unsupported argument for source-list: project/daymark"
            )
        }
    }

    func testCodexContextRendererListsMatchingTaskSpecsAndBundles() throws {
        let invocation = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark codex-context #project/daymark",
            command: .codexContext,
            arguments: ["#project/daymark"],
            ordinal: 1
        )
        let contexts = [
            DynamicBlockCodexContextArtifact(
                kind: .contextBundle,
                title: "Context Bundle: Ship beta",
                relativePath: "artifacts/context-bundles/2026-06-29-ship-beta-context.md",
                tags: ["#project/daymark"],
                sourcePaths: ["projects/daymark.md"],
                taskPaths: ["specs/tasks/2026-06-29-ship-beta.md"]
            ),
            DynamicBlockCodexContextArtifact(
                kind: .taskSpec,
                title: "Ship beta",
                relativePath: "specs/tasks/2026-06-29-ship-beta.md",
                tags: ["#project/daymark"],
                sourcePaths: ["projects/daymark.md"],
                taskPaths: []
            ),
            DynamicBlockCodexContextArtifact(
                kind: .taskSpec,
                title: "Other task",
                relativePath: "specs/tasks/2026-06-29-other.md",
                tags: ["#project/other"],
                sourcePaths: [],
                taskPaths: []
            )
        ]

        let rendered = try DynamicBlockRenderer().render(
            invocation: invocation,
            tasks: [],
            sources: [],
            codexContexts: contexts,
            referenceDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(rendered.contains("### Codex Context: #project/daymark"))
        XCTAssertTrue(rendered.contains("#### Task Specs"))
        XCTAssertTrue(rendered.contains("- Ship beta (`specs/tasks/2026-06-29-ship-beta.md`) source: `projects/daymark.md`"))
        XCTAssertTrue(rendered.contains("#### Context Bundles"))
        XCTAssertTrue(rendered.contains("- Context Bundle: Ship beta (`artifacts/context-bundles/2026-06-29-ship-beta-context.md`) task: `specs/tasks/2026-06-29-ship-beta.md`; source: `projects/daymark.md`"))
        XCTAssertFalse(rendered.contains("Other task"))
    }

    func testCodexContextRendererRejectsMalformedArgumentsAndShowsPlainEmptyState() throws {
        let renderer = DynamicBlockRenderer()
        let missingArgument = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark codex-context",
            command: .codexContext,
            ordinal: 1
        )
        let empty = try renderer.render(
            invocation: missingArgument,
            tasks: [],
            sources: [],
            codexContexts: [],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(empty, "### Codex Context\n\nAdd a tag argument, for example `#project/daymark`.\n")

        let malformed = DynamicBlockInvocation(
            sourcePath: "daily/today.md",
            lineNumber: 1,
            rawText: "/daymark codex-context project/daymark",
            command: .codexContext,
            arguments: ["project/daymark"],
            ordinal: 1
        )
        XCTAssertThrowsError(try renderer.render(
            invocation: malformed,
            tasks: [],
            sources: [],
            codexContexts: [],
            referenceDate: Date(timeIntervalSince1970: 0)
        )) { error in
            XCTAssertEqual(
                (error as? DynamicBlockError)?.errorDescription,
                "unsupported argument for codex-context: project/daymark"
            )
        }
    }

    func testWeeklyReviewRendererIncludesOpenTasksCompletedTasksAndRecentHandoffs() throws {
        let invocation = DynamicBlockInvocation(
            sourcePath: "planning/week.md",
            lineNumber: 1,
            rawText: "/daymark weekly-review",
            command: .weeklyReview,
            ordinal: 1
        )
        let tasks = [
            TaskItem(title: "ship the review block due:2026-06-29", status: .open, due: .date("2026-06-29"), notePath: "daily/2026/06/2026-06-29.md", lineNumber: 4),
            TaskItem(title: "close out old handoff", status: .completed, notePath: "daily/2026/06/2026-06-28.md", lineNumber: 7),
            TaskItem(title: "completed outside week", status: .completed, notePath: "daily/2026/06/2026-06-20.md", lineNumber: 2)
        ]
        let sources = [
            DynamicBlockSource(title: "Daymark Project", relativePath: "projects/daymark.md", tags: ["#project/daymark"])
        ]
        let contexts = [
            DynamicBlockCodexContextArtifact(
                kind: .taskSpec,
                title: "Ship weekly review",
                relativePath: "specs/tasks/2026-06-29-ship-weekly-review.md",
                tags: ["#project/daymark"],
                sourcePaths: ["projects/daymark.md"]
            ),
            DynamicBlockCodexContextArtifact(
                kind: .contextBundle,
                title: "Context Bundle: Ship weekly review",
                relativePath: "artifacts/context-bundles/2026-06-29-ship-weekly-review-context.md",
                tags: ["#project/daymark"],
                sourcePaths: ["projects/daymark.md"],
                taskPaths: ["specs/tasks/2026-06-29-ship-weekly-review.md"]
            ),
            DynamicBlockCodexContextArtifact(
                kind: .taskSpec,
                title: "Old handoff",
                relativePath: "specs/tasks/2026-06-15-old.md",
                tags: ["#project/daymark"],
                sourcePaths: ["projects/old.md"]
            )
        ]

        let rendered = try DynamicBlockRenderer().render(
            invocation: invocation,
            tasks: tasks,
            sources: sources,
            codexContexts: contexts,
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )

        XCTAssertTrue(rendered.contains("### Weekly Review"))
        XCTAssertTrue(rendered.contains("#### Still Open"))
        XCTAssertTrue(rendered.contains("- [ ] ship the review block due:2026-06-29  (daily/2026/06/2026-06-29.md:4)"))
        XCTAssertTrue(rendered.contains("#### Completed This Week"))
        XCTAssertTrue(rendered.contains("- [x] close out old handoff  (daily/2026/06/2026-06-28.md:7)"))
        XCTAssertFalse(rendered.contains("completed outside week"))
        XCTAssertTrue(rendered.contains("#### Codex Handoffs"))
        XCTAssertTrue(rendered.contains("- Task: Ship weekly review (`specs/tasks/2026-06-29-ship-weekly-review.md`) source: `projects/daymark.md`"))
        XCTAssertTrue(rendered.contains("- Bundle: Context Bundle: Ship weekly review (`artifacts/context-bundles/2026-06-29-ship-weekly-review-context.md`) task: `specs/tasks/2026-06-29-ship-weekly-review.md`; source: `projects/daymark.md`"))
        XCTAssertFalse(rendered.contains("Old handoff"))
        XCTAssertTrue(rendered.contains("#### Sources To Revisit"))
        XCTAssertTrue(rendered.contains("- Daymark Project (`projects/daymark.md`)"))
    }

    func testWeeklyReviewRendererRejectsArgumentsAndShowsPlainEmptyStates() throws {
        let renderer = DynamicBlockRenderer()
        let invocation = DynamicBlockInvocation(
            sourcePath: "planning/week.md",
            lineNumber: 1,
            rawText: "/daymark weekly-review",
            command: .weeklyReview,
            ordinal: 1
        )

        let rendered = try renderer.render(
            invocation: invocation,
            tasks: [],
            sources: [],
            codexContexts: [],
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )
        XCTAssertEqual(rendered, """
        ### Weekly Review

        #### Still Open
        No open loops.

        #### Completed This Week
        No completed tasks found for this week.

        #### Codex Handoffs
        No Codex handoffs found for this week.

        #### Sources To Revisit
        No source notes found from this week's handoffs.

        """)

        let malformed = DynamicBlockInvocation(
            sourcePath: "planning/week.md",
            lineNumber: 1,
            rawText: "/daymark weekly-review #project/daymark",
            command: .weeklyReview,
            arguments: ["#project/daymark"],
            ordinal: 1
        )
        XCTAssertThrowsError(try renderer.render(
            invocation: malformed,
            tasks: [],
            sources: [],
            codexContexts: [],
            referenceDate: date("2026-06-29"),
            calendar: calendar
        )) { error in
            XCTAssertEqual(
                (error as? DynamicBlockError)?.errorDescription,
                "unsupported argument for weekly-review: #project/daymark"
            )
        }
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
            sources: [],
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
            sources: [],
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

    func testContainsKnownCommandIgnoresUnsupportedAlongsideValid() {
        // A note with a valid command and an unsupported one must still report true; parse()
        // throws on the unsupported line, so the gating detector cannot route through it.
        let markdown = """
        # Today

        /daymark not-a-real-command
        /daymark open-loops
        """
        XCTAssertTrue(DynamicBlockParser().containsKnownCommand(in: markdown))
    }

    func testContainsKnownCommandIgnoresCommandsInsideFences() {
        let markdown = """
        # Today

        ```
        /daymark open-loops
        ```
        """
        XCTAssertFalse(DynamicBlockParser().containsKnownCommand(in: markdown))
    }
}
