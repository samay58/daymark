import XCTest
import DaymarkCore
@testable import DaymarkIndexer

final class MarkdownParserTests: XCTestCase {
    private let parser = MarkdownParser()

    func testCreatesLineBlocks() {
        let blocks = parser.blocks(from: "# Today\n\nBody")

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.first?.lineStart, 1)
        XCTAssertEqual(blocks.last?.markdown, "Body")
    }

    func testTitleUsesFirstHeading() {
        XCTAssertEqual(parser.title(from: "# Sunday, June 28\n\n## Brief\n"), "Sunday, June 28")
        XCTAssertEqual(parser.title(from: "## Section only\n"), "Section only")
    }

    func testTitleFallsBackToFirstNonEmptyLine() {
        XCTAssertEqual(parser.title(from: "\n\nplain first line\nmore"), "plain first line")
        XCTAssertNil(parser.title(from: "\n\n   \n"))
    }

    func testTitleOfDefaultTemplateMatchesHeading() {
        let date = makeDate(year: 2026, month: 6, day: 22)
        let template = DailyNote.defaultTemplate(for: date, calendar: posixCalendar())
        XCTAssertEqual(parser.title(from: template), "Monday, June 22")
    }

    func testParsesRealisticDailyNote() {
        // The daily-note shape from docs/PRODUCT_SPEC.md.
        let note = """
        # Monday, June 22

        ## Brief

        - 10:30 Acme founder call

        ## Capture

        - [ ] Ask Sarah for updated model assumptions #deal/acme @sarah due:today

        ## Decisions

        - Markdown remains the human-readable source of truth.
        """

        XCTAssertEqual(parser.title(from: note), "Monday, June 22")

        let blocks = parser.blocks(from: note)
        let lines = note.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(blocks.count, lines.count, "one block per source line")

        // The task line survives verbatim, including tags and metadata, so nothing is lost.
        let taskBlock = blocks.first { $0.markdown.contains("- [ ] Ask Sarah") }
        XCTAssertNotNil(taskBlock)
        XCTAssertTrue(taskBlock?.markdown.contains("#deal/acme @sarah due:today") ?? false)

        // The heading is block one and keeps its marker.
        XCTAssertEqual(blocks.first?.markdown, "# Monday, June 22")
    }

    // MARK: - Helpers

    private func posixCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        posixCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: 9)) ?? Date(timeIntervalSince1970: 0)
    }
}
