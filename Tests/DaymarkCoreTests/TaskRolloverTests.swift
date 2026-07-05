import XCTest
@testable import DaymarkCore

final class TaskRolloverTests: XCTestCase {
    private let yesterdayPath = "daily/2026/06/2026-06-27.md"
    private let todayPath = "daily/2026/06/2026-06-28.md"

    private func task(
        _ title: String,
        status: TaskItem.Status = .open,
        notePath: String,
        line: Int = 5,
        originalLine: String? = nil
    ) -> TaskItem {
        TaskItem(
            title: title,
            status: status,
            notePath: notePath,
            lineNumber: line,
            originalLine: originalLine ?? "- [ ] \(title)"
        )
    }

    func testPlansRolloverForOpenTasksFromPriorDailyNotes() {
        let today = "# Today\n\n## Brief\n\n## Capture\n"
        let plan = TaskRollover.plan(
            tasks: [
                task("follow up with Sarah #deal/acme", notePath: yesterdayPath),
                task("today task", notePath: todayPath)
            ],
            todayMarkdown: today,
            todayPath: todayPath
        )

        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertTrue(plan.updatedMarkdown.contains("- From yesterday: follow up with Sarah #deal/acme"))
        XCTAssertTrue(plan.updatedMarkdown.contains("from daily/2026/06/2026-06-27.md:5"))
        XCTAssertEqual(plan.updatedMarkdown.components(separatedBy: "## Brief").count - 1, 1)
        XCTAssertTrue(plan.updatedMarkdown.contains(TaskRollover.marker(for: task("follow up with Sarah #deal/acme", notePath: yesterdayPath))))
    }

    func testExcludesCompletedTasksAndNonDailyNotes() {
        let plan = TaskRollover.plan(
            tasks: [
                task("done", status: .completed, notePath: yesterdayPath, originalLine: "- [x] done"),
                task("project task", notePath: "projects/acme.md")
            ],
            todayMarkdown: "# Today\n\n## Brief\n",
            todayPath: todayPath
        )

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertFalse(plan.updatedMarkdown.contains("From yesterday:"))
    }

    func testDoesNotDuplicateRolloverAlreadyMarkedInTodayMarkdown() {
        let source = task("follow up with Sarah", notePath: yesterdayPath)
        let marker = TaskRollover.marker(for: source)
        let today = """
        # Today

        ## Brief

        - Rolled over: follow up with Sarah (from daily/2026/06/2026-06-27.md:5) \(marker)

        ## Capture
        """

        let plan = TaskRollover.plan(
            tasks: [source],
            todayMarkdown: today,
            todayPath: todayPath
        )

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.updatedMarkdown, today + "\n")
    }

    func testDedupsAgainstPreExistingOldProseEntry() {
        // Notes written before the copy change still have "Rolled over:" prose on disk.
        // Dedup keys on the HTML comment marker hash, not the prose, so these must still
        // be recognized and skipped.
        let source = task("follow up with Sarah", notePath: yesterdayPath)
        let marker = TaskRollover.marker(for: source)
        let today = """
        # Today

        ## Brief

        - Rolled over: follow up with Sarah (from daily/2026/06/2026-06-27.md:5) \(marker)

        ## Capture
        """

        let plan = TaskRollover.plan(
            tasks: [source],
            todayMarkdown: today,
            todayPath: todayPath
        )

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.updatedMarkdown, today + "\n")
    }

    func testUsesWeekdayPrefixForTwoToSixDaysPrior() {
        // 2026-06-28 is a Sunday; a task from Wednesday 2026-06-24 is four days prior.
        let plan = TaskRollover.plan(
            tasks: [task("send the deck", notePath: "daily/2026/06/2026-06-24.md")],
            todayMarkdown: "# Today\n\n## Brief\n",
            todayPath: todayPath
        )

        XCTAssertTrue(plan.updatedMarkdown.contains("- From Wednesday: send the deck"), plan.updatedMarkdown)
    }

    func testUsesMonthDayPrefixForOlderThanSixDays() {
        let plan = TaskRollover.plan(
            tasks: [task("renew the lease", notePath: "daily/2026/06/2026-06-18.md")],
            todayMarkdown: "# Today\n\n## Brief\n",
            todayPath: todayPath
        )

        XCTAssertTrue(plan.updatedMarkdown.contains("- From Jun 18: renew the lease"), plan.updatedMarkdown)
    }

    func testRolloverKeepsTodayMarkdownReadable() {
        let plan = TaskRollover.plan(
            tasks: [task("review memo", notePath: yesterdayPath)],
            todayMarkdown: "# Today\n\n## Brief\n\n## Decisions\n",
            todayPath: todayPath
        )

        XCTAssertTrue(plan.updatedMarkdown.contains("## Brief\n\n- From yesterday: review memo"))
        XCTAssertTrue(plan.updatedMarkdown.contains("<!-- daymark-rollover:"))
        XCTAssertTrue(plan.updatedMarkdown.contains("\n\n## Decisions\n"))
    }
}
