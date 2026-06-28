import XCTest
@testable import DaymarkCore

final class DailyNoteTests: XCTestCase {
    private func calendar(timeZone identifier: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: identifier) ?? .current
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in cal: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return cal.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func testRelativePathFollowsDailyYearMonthDay() {
        let cal = calendar(timeZone: "America/Los_Angeles")
        let d = date(2026, 6, 28, in: cal)
        XCTAssertEqual(DailyNote.relativePath(for: d, calendar: cal), "daily/2026/06/2026-06-28.md")
    }

    func testRelativePathZeroPadsSingleDigits() {
        let cal = calendar(timeZone: "America/Los_Angeles")
        let d = date(2026, 1, 5, in: cal)
        XCTAssertEqual(DailyNote.relativePath(for: d, calendar: cal), "daily/2026/01/2026-01-05.md")
    }

    func testFileURLJoinsRootAndRelativePath() {
        let cal = calendar(timeZone: "America/Los_Angeles")
        let d = date(2026, 6, 28, in: cal)
        let root = WorkspaceRoot(path: "/tmp/ws")
        let url = DailyNote.fileURL(in: root, for: d, calendar: cal)
        XCTAssertEqual(url.path, "/tmp/ws/daily/2026/06/2026-06-28.md")
    }

    func testTemplateIsReadableMarkdownWithDocumentedSections() {
        let cal = calendar(timeZone: "America/Los_Angeles")
        let d = date(2026, 6, 28, in: cal)
        let template = DailyNote.defaultTemplate(for: d, calendar: cal)

        XCTAssertTrue(template.hasPrefix("# "), "should open with an H1 title")
        XCTAssertTrue(template.contains("Sunday, June 28"), "title should be human-readable weekday + date")
        XCTAssertTrue(template.contains("## Brief"))
        XCTAssertTrue(template.contains("## Capture"))
        XCTAssertFalse(template.contains("—"), "no em-dashes in generated content")
    }
}
