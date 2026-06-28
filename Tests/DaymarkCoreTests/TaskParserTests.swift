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
}
