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
        XCTAssertTrue(plan.updatedMarkdown.contains("- Rolled over: follow up with Sarah #deal/acme"))
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
        XCTAssertFalse(plan.updatedMarkdown.contains("Rolled over:"))
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

    func testRolloverKeepsTodayMarkdownReadable() {
        let plan = TaskRollover.plan(
            tasks: [task("review memo", notePath: yesterdayPath)],
            todayMarkdown: "# Today\n\n## Brief\n\n## Decisions\n",
            todayPath: todayPath
        )

        XCTAssertTrue(plan.updatedMarkdown.contains("## Brief\n\n- Rolled over: review memo"))
        XCTAssertTrue(plan.updatedMarkdown.contains("<!-- daymark-rollover:"))
        XCTAssertTrue(plan.updatedMarkdown.contains("\n\n## Decisions\n"))
    }
}
