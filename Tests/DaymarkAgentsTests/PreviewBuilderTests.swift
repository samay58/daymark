import XCTest
import DaymarkCore
@testable import DaymarkAgents

final class PreviewBuilderTests: XCTestCase {
    func testPreviewIsDeterministicAndReadable() throws {
        let source = SourceSelection(
            excerpt: """
            Make the Open Loops view show grouped tasks from the SQLite projection.
            Keep it read-only for now.
            """,
            sourcePath: "daily/2026/06/2026-06-29.md",
            startLine: 14,
            endLine: 15,
            heading: "Capture"
        )

        let first = try PreviewBuilder().codexTaskPreview(
            source: source,
            date: fixedDate(),
            existingRelativePaths: []
        )
        let second = try PreviewBuilder().codexTaskPreview(
            source: source,
            date: fixedDate(),
            existingRelativePaths: []
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.title, "Make the Open Loops view show grouped tasks")
        XCTAssertEqual(
            first.goal,
            "Make the Open Loops view show grouped tasks from the SQLite projection. Keep it read-only for now."
        )
        XCTAssertFalse(first.goal.contains("Implement this source note"))
        XCTAssertEqual(first.sourceLine, 14)
        XCTAssertEqual(first.sourceBlock, "Capture")
        XCTAssertEqual(first.suggestedFilePath, "specs/tasks/2026-06-29-make-the-open-loops-view-show-grouped-tasks.md")
        XCTAssertTrue(first.acceptanceCriteria.contains("Source note remains unchanged"))
        XCTAssertTrue(first.acceptanceCriteria.contains("Source excerpt is preserved in the task file"))
        XCTAssertTrue(first.markdown().contains("```md\nMake the Open Loops view"))
    }

    func testPreviewChoosesCollisionSafeSuggestedPath() throws {
        let source = SourceSelection(
            excerpt: "Make rollover deterministic.",
            sourcePath: "daily/2026/06/2026-06-29.md",
            startLine: 8,
            endLine: 8,
            heading: nil
        )

        let draft = try PreviewBuilder().codexTaskPreview(
            source: source,
            date: fixedDate(),
            existingRelativePaths: [
                "specs/tasks/2026-06-29-make-rollover-deterministic.md",
                "specs/tasks/2026-06-29-make-rollover-deterministic-2.md"
            ]
        )

        XCTAssertEqual(draft.suggestedFilePath, "specs/tasks/2026-06-29-make-rollover-deterministic-3.md")
    }

    func testEmptySourceSelectionIsRejected() {
        let source = SourceSelection(
            excerpt: "  ",
            sourcePath: "daily/2026/06/2026-06-29.md",
            startLine: nil,
            endLine: nil,
            heading: nil
        )

        XCTAssertThrowsError(
            try PreviewBuilder().codexTaskPreview(
                source: source,
                date: fixedDate(),
                existingRelativePaths: []
            )
        )
    }

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 29
        components.hour = 12
        return components.date!
    }
}
