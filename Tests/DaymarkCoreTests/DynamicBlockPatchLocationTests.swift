import XCTest
@testable import DaymarkCore

/// A patch must name the region it rewrites and the command line it belongs to in terms the
/// editor can use directly: the begin-marker hash its scan sees, and a UTF-16 range in the
/// unnormalized text. The editor splits lines differently from the planner, so line numbers
/// alone point at the wrong line.
final class DynamicBlockPatchLocationTests: XCTestCase {
    private let tasks = [TaskItem(title: "follow up", status: .open, notePath: "daily/a.md", lineNumber: 7)]
    private let sources = [DynamicBlockSource(title: "Project", relativePath: "projects/x.md", tags: ["#project/x"])]

    private func plan(_ markdown: String) throws -> DynamicBlockPatchPlan {
        try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: tasks,
            sources: sources,
            referenceDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func patch(_ plan: DynamicBlockPatchPlan, _ command: DynamicBlockCommand) throws -> DynamicBlockPatch {
        try XCTUnwrap(plan.patches.first { $0.command == command })
    }

    func testLineSeparatorsAboveBlocksKeepEachPatchOnItsOwnRegion() throws {
        // NSString line enumeration breaks on U+2028; the planner does not. Seven of them put
        // the editor's line numbers seven past the planner's, enough to land the second block's
        // command line where the first block's is.
        let separators = String(repeating: "\u{2028}", count: 7)
        let markdown = [
            "Intro \(separators) text",
            "/daymark open-loops",
            "<!-- daymark:block-begin aaaaaaaaaaaa -->",
            "stale loops",
            "<!-- daymark:block-end aaaaaaaaaaaa -->",
            "/daymark source-list #project/x",
            "<!-- daymark:block-begin bbbbbbbbbbbb -->",
            "stale sources",
            "<!-- daymark:block-end bbbbbbbbbbbb -->"
        ].joined(separator: "\n")
        let ns = markdown as NSString
        let plan = try plan(markdown)

        let loops = try patch(plan, .openLoops)
        let list = try patch(plan, .sourceList)
        XCTAssertEqual(loops.existingRegionHash, "aaaaaaaaaaaa")
        XCTAssertEqual(list.existingRegionHash, "bbbbbbbbbbbb")
        XCTAssertEqual(ns.substring(with: loops.commandLineRange), "/daymark open-loops")
        XCTAssertEqual(ns.substring(with: list.commandLineRange), "/daymark source-list #project/x")
        XCTAssertTrue(loops.changesMarkdown)
        XCTAssertTrue(list.changesMarkdown)

        // The editor's scan agrees on which command line sits above each region.
        let regions = NoteTokenScanner.scan(markdown).regions
        let byHash = Dictionary(uniqueKeysWithValues: regions.map { ($0.hash, $0) })
        XCTAssertEqual(byHash["aaaaaaaaaaaa"]?.commandLineRange, loops.commandLineRange)
        XCTAssertEqual(byHash["bbbbbbbbbbbb"]?.commandLineRange, list.commandLineRange)
    }

    func testInsertRangeSkipsLineSeparatorsAbove() throws {
        let markdown = "One\u{2028}two\u{2029}three\u{0085}four\n/daymark open-loops\nAfter"
        let insert = try patch(try plan(markdown), .openLoops)
        XCTAssertEqual(insert.operation, .insert)
        XCTAssertNil(insert.existingRegionHash)
        XCTAssertEqual((markdown as NSString).substring(with: insert.commandLineRange), "/daymark open-loops")
    }

    func testTrailingSpaceClosingFenceStillEndsTheFence() throws {
        let markdown = [
            "```",
            "code",
            "``` ",
            "/daymark open-loops",
            "<!-- daymark:block-begin aaaaaaaaaaaa -->",
            "stale",
            "<!-- daymark:block-end aaaaaaaaaaaa -->"
        ].joined(separator: "\n")
        let loops = try patch(try plan(markdown), .openLoops)
        XCTAssertEqual(loops.existingRegionHash, "aaaaaaaaaaaa")
        XCTAssertEqual((markdown as NSString).substring(with: loops.commandLineRange), "/daymark open-loops")

        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(tokens.lines[3].kind, .commandLine(command: "open-loops"))
        XCTAssertEqual(tokens.regions.first?.commandLineRange, loops.commandLineRange)
        XCTAssertFalse(NoteTokenCacheReducer.fenceStates(for: markdown)[3].fence.isInsideFence)
    }

    func testUpToDateRegionIsUnchangedUnderEveryLineEnding() throws {
        let lf = try plan("Intro\n/daymark open-loops\nOutro").apply(to: "Intro\n/daymark open-loops\nOutro")
        for ending in ["\n", "\r\n", "\r"] {
            let markdown = lf.replacingOccurrences(of: "\n", with: ending)
            let loops = try patch(try plan(markdown), .openLoops)
            XCTAssertEqual(loops.operation, .replacement, "ending \(ending.debugDescription)")
            XCTAssertFalse(loops.changesMarkdown, "ending \(ending.debugDescription)")
            XCTAssertEqual(loops.existingRegionHash, loops.commandHash, "ending \(ending.debugDescription)")
            XCTAssertEqual(
                (markdown as NSString).substring(with: loops.commandLineRange),
                "/daymark open-loops",
                "ending \(ending.debugDescription)"
            )
        }
    }

    func testLineRangesMatchNormalizedSplit() {
        let markdown = "a\r\nb\rc\nd\u{2028}e\r\r\nf\n"
        let normalizedLines = markdown.normalizedNewlines.components(separatedBy: "\n")
        let ranges = MarkdownLineRanges.utf16Ranges(in: markdown)
        XCTAssertEqual(ranges.map { (markdown as NSString).substring(with: $0) }, normalizedLines)
    }
}
