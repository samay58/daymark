import XCTest
@testable import DaymarkCore

final class TaskParserTests: XCTestCase {
    func testParsesOpenAndCompletedTasks() {
        let markdown = """
        - [ ] Ask Sarah for model assumptions #deal/acme @sarah due:today
        - [x] Create governance docs
        """

        let tasks = TaskParser().parse(markdown: markdown)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].status, .open)
        XCTAssertEqual(tasks[0].tags, ["#deal/acme"])
        XCTAssertEqual(tasks[0].mentions, ["@sarah"])
        XCTAssertEqual(tasks[1].status, .completed)
    }

    func testParsesUppercaseCompletedMarker() {
        let tasks = TaskParser().parse(markdown: "- [X] Done with a capital X")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testIgnoresCheckboxesInsideFencedCodeBlocks() {
        let markdown = """
        - [ ] real task

        ```
        - [ ] not a task, this is sample code
        - [x] also not a task
        ```

        - [x] another real task
        """

        let tasks = TaskParser().parse(markdown: markdown)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].title, "real task")
        XCTAssertEqual(tasks[1].title, "another real task")
    }

    func testKeepsTitleHumanReadableWithMetadataInline() {
        // Tags, mentions, and due tokens are extracted as metadata but stay in the title,
        // so the line round-trips to the same readable Markdown.
        let tasks = TaskParser().parse(markdown: "- [ ] Send memo #deal/acme @sarah due:today")
        XCTAssertEqual(tasks[0].title, "Send memo #deal/acme @sarah due:today")
    }

    func testExtractsTagsAndMentions() {
        let tasks = TaskParser().parse(markdown: "- [ ] Plan #q3 #deal/acme with @sarah and @lee")
        XCTAssertEqual(tasks[0].tags, ["#q3", "#deal/acme"])
        XCTAssertEqual(tasks[0].mentions, ["@sarah", "@lee"])
    }

    func testExtractsDueTodayTomorrowAndIsoDate() {
        let today = TaskParser().parse(markdown: "- [ ] a due:today")
        XCTAssertEqual(today[0].due, .today)

        let tomorrow = TaskParser().parse(markdown: "- [ ] b due:tomorrow")
        XCTAssertEqual(tomorrow[0].due, .tomorrow)

        let dated = TaskParser().parse(markdown: "- [ ] c due:2026-06-29")
        XCTAssertEqual(dated[0].due, .date("2026-06-29"))
    }

    func testDoesNotExtractNaturalLanguageDueAsStructuredDate() {
        // We do not resolve natural-language dates yet; only today/tomorrow/ISO are structured.
        let tasks = TaskParser().parse(markdown: "- [ ] d due:next-week")
        XCTAssertNil(tasks[0].due)
        XCTAssertEqual(tasks[0].title, "d due:next-week", "unrecognized due token stays in the title")
    }

    func testRecordsLineNumbersAndOriginalLine() {
        let markdown = """
        # Tuesday

        ## Capture

        - [ ] first task
          - [x] indented subtask
        """

        let tasks = TaskParser().parse(markdown: markdown)

        XCTAssertEqual(tasks[0].title, "first task")
        XCTAssertEqual(tasks[0].lineNumber, 5)
        XCTAssertEqual(tasks[0].originalLine, "- [ ] first task")
        XCTAssertEqual(tasks[1].title, "indented subtask")
        XCTAssertEqual(tasks[1].lineNumber, 6)
        XCTAssertEqual(tasks[1].originalLine, "  - [x] indented subtask")
    }

    func testRecordsSectionHeading() {
        let markdown = """
        # Tuesday

        ## Brief

        - [ ] brief task

        ## Capture

        - [ ] capture task
        """

        let tasks = TaskParser().parse(markdown: markdown)

        XCTAssertEqual(tasks[0].sectionHeading, "Brief")
        XCTAssertEqual(tasks[1].sectionHeading, "Capture")
    }

    func testTasksBeforeAnyHeadingHaveNoSection() {
        let tasks = TaskParser().parse(markdown: "- [ ] orphan task")
        XCTAssertNil(tasks[0].sectionHeading)
    }

    func testStampsNotePathWhenProvided() {
        let path = "daily/2026/06/2026-06-28.md"
        let tasks = TaskParser().parse(markdown: "- [ ] do thing", notePath: path)
        XCTAssertEqual(tasks[0].notePath, path)
    }

    func testHandlesCarriageReturnLineEndings() {
        let markdown = "## Capture\r\n\r\n- [ ] crlf task\r\n"
        let tasks = TaskParser().parse(markdown: markdown)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "crlf task")
        XCTAssertEqual(tasks[0].sectionHeading, "Capture")
    }
}
