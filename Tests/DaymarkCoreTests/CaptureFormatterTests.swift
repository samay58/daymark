import XCTest
@testable import DaymarkCore

final class CaptureFormatterTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return c
    }

    private func dateAt(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func testTimestampIsZeroPaddedTwentyFourHour() {
        XCTAssertEqual(CaptureFormatter.timestamp(for: dateAt(hour: 9, minute: 5), calendar: calendar), "09:05")
        XCTAssertEqual(CaptureFormatter.timestamp(for: dateAt(hour: 21, minute: 30), calendar: calendar), "21:30")
    }

    func testDayHeadingIsLevelTwoIsoDate() {
        XCTAssertEqual(CaptureFormatter.dayHeading(for: dateAt(hour: 9, minute: 30), calendar: calendar), "## 2026-06-28")
    }

    func testTimestampedBulletSingleLine() {
        let bullet = CaptureFormatter.timestampedBullet("buy milk", at: dateAt(hour: 9, minute: 30), calendar: calendar)
        XCTAssertEqual(bullet, "- 09:30 buy milk")
    }

    func testTimestampedBulletMultilineIndentsContinuations() {
        let bullet = CaptureFormatter.timestampedBullet("buy milk\nand eggs", at: dateAt(hour: 9, minute: 30), calendar: calendar)
        XCTAssertEqual(bullet, "- 09:30 buy milk\n  and eggs")
    }

    func testTimestampedBulletTrimsAndDropsBlankLines() {
        let bullet = CaptureFormatter.timestampedBullet("  buy milk \n\n  and eggs  ", at: dateAt(hour: 9, minute: 30), calendar: calendar)
        XCTAssertEqual(bullet, "- 09:30 buy milk\n  and eggs")
    }

    func testTaskLineSingleLine() {
        XCTAssertEqual(CaptureFormatter.taskLine("write the spec"), "- [ ] write the spec")
    }

    func testTaskLineMultilineIndentsContinuations() {
        XCTAssertEqual(CaptureFormatter.taskLine("write the spec\ntonight"), "- [ ] write the spec\n  tonight")
    }

    func testTaskLineTrimsWhitespace() {
        XCTAssertEqual(CaptureFormatter.taskLine("  write the spec  "), "- [ ] write the spec")
    }

    func testTimestampHandlesMidnightAndNoon() {
        XCTAssertEqual(CaptureFormatter.timestamp(for: dateAt(hour: 0, minute: 0), calendar: calendar), "00:00")
        XCTAssertEqual(CaptureFormatter.timestamp(for: dateAt(hour: 12, minute: 0), calendar: calendar), "12:00")
        XCTAssertEqual(CaptureFormatter.timestamp(for: dateAt(hour: 23, minute: 59), calendar: calendar), "23:59")
    }
}
