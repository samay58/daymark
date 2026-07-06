import XCTest
@testable import DaymarkCore

final class TaskItemTests: XCTestCase {
    func testDueDisplayTextForRelativeTokens() {
        XCTAssertEqual(TaskItem.Due.today.displayText(), "Today")
        XCTAssertEqual(TaskItem.Due.tomorrow.displayText(), "Tomorrow")
    }

    func testDueDisplayTextForISODate() {
        XCTAssertEqual(TaskItem.Due.date("2026-07-08").displayText(), "Jul 8")
    }

    func testDueDisplayTextFallsBackToRawDateToken() {
        XCTAssertEqual(TaskItem.Due.date("not-a-date").displayText(), "not-a-date")
    }
}
