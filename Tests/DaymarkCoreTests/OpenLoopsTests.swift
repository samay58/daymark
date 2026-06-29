import XCTest
@testable import DaymarkCore

final class OpenLoopsTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func task(_ title: String, status: TaskItem.Status = .open, due: TaskItem.Due? = nil, mentions: [String] = []) -> TaskItem {
        TaskItem(title: title, status: status, mentions: mentions, due: due)
    }

    func testExcludesCompletedTasks() {
        let groups = OpenLoops.grouped(
            tasks: [task("done", status: .completed, due: .today), task("open", due: .today)],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        let titles = groups.flatMap { $0.tasks.map(\.title) }
        XCTAssertEqual(titles, ["open"], "completed tasks never appear in Open Loops")
    }

    func testBucketsDueTodayFromTokenAndMatchingDate() {
        let groups = OpenLoops.grouped(
            tasks: [task("token", due: .today), task("dated", due: .date("2026-06-28"))],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        let dueToday = groups.first { $0.bucket == .dueToday }
        XCTAssertEqual(dueToday?.tasks.map(\.title), ["token", "dated"])
    }

    func testBucketsOverdueAndUpcomingByDate() {
        let groups = OpenLoops.grouped(
            tasks: [task("past", due: .date("2026-06-01")), task("future", due: .date("2026-07-01")), task("tomorrow", due: .tomorrow)],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        XCTAssertEqual(groups.first { $0.bucket == .overdue }?.tasks.map(\.title), ["past"])
        XCTAssertEqual(groups.first { $0.bucket == .upcoming }?.tasks.map(\.title), ["future", "tomorrow"])
    }

    func testUndatedTasksSplitByWaitingMarker() {
        let groups = OpenLoops.grouped(
            tasks: [task("ping vendor @lee", mentions: ["@lee"]), task("waiting: legal review"), task("write memo")],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        XCTAssertEqual(groups.first { $0.bucket == .waitingOnOthers }?.tasks.map(\.title), ["ping vendor @lee", "waiting: legal review"])
        XCTAssertEqual(groups.first { $0.bucket == .noDate }?.tasks.map(\.title), ["write memo"])
    }

    func testDatedTaskWithMentionStaysInDateBucket() {
        // A task that has both a date and a mention is bucketed by its date, not as waiting.
        let groups = OpenLoops.grouped(
            tasks: [task("review with @sarah", due: .today, mentions: ["@sarah"])],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        XCTAssertEqual(groups.first { $0.bucket == .dueToday }?.tasks.map(\.title), ["review with @sarah"])
        XCTAssertNil(groups.first { $0.bucket == .waitingOnOthers })
    }

    func testReturnsGroupsInBucketOrderAndOmitsEmpty() {
        let groups = OpenLoops.grouped(
            tasks: [task("later", due: .tomorrow), task("now", due: .today), task("idle")],
            on: date("2026-06-28"),
            calendar: utcCalendar()
        )
        XCTAssertEqual(groups.map(\.bucket), [.dueToday, .upcoming, .noDate], "non-empty buckets only, in display order")
    }
}
