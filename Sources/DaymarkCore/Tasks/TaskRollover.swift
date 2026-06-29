import Foundation

public struct RolloverEntry: Equatable, Sendable {
    public var task: TaskItem
    public var marker: String
    public var markdownLine: String

    public init(task: TaskItem, marker: String, markdownLine: String) {
        self.task = task
        self.marker = marker
        self.markdownLine = markdownLine
    }
}

public struct RolloverPlan: Equatable, Sendable {
    public var entries: [RolloverEntry]
    public var updatedMarkdown: String

    public init(entries: [RolloverEntry], updatedMarkdown: String) {
        self.entries = entries
        self.updatedMarkdown = updatedMarkdown
    }
}

public enum TaskRollover {
    public static let briefHeading = "## Brief"

    public static func marker(for task: TaskItem) -> String {
        "<!-- daymark-rollover:\(ContentHasher.hash(task.sourceKey)) -->"
    }

    public static func plan(
        tasks: [TaskItem],
        todayMarkdown: String,
        todayPath: String
    ) -> RolloverPlan {
        let normalizedToday = normalized(todayMarkdown)
        var entries: [RolloverEntry] = []

        for task in tasks where shouldRoll(task, before: todayPath, in: normalizedToday) {
            let marker = marker(for: task)
            let source = "\(task.notePath):\(task.lineNumber)"
            let line = "- Rolled over: \(task.title) (from \(source)) \(marker)"
            entries.append(RolloverEntry(task: task, marker: marker, markdownLine: line))
        }

        guard !entries.isEmpty else {
            return RolloverPlan(entries: [], updatedMarkdown: normalizedToday)
        }

        let block = entries.map(\.markdownLine).joined(separator: "\n")
        let updated = MarkdownSection.appendingEntry(block, under: briefHeading, to: normalizedToday)
        return RolloverPlan(entries: entries, updatedMarkdown: updated)
    }

    private static func shouldRoll(_ task: TaskItem, before todayPath: String, in todayMarkdown: String) -> Bool {
        guard task.status == .open,
              isDailyPath(task.notePath),
              task.notePath < todayPath,
              !todayMarkdown.contains(marker(for: task)) else {
            return false
        }
        return true
    }

    private static func isDailyPath(_ path: String) -> Bool {
        let pattern = #"^daily/\d{4}/\d{2}/\d{4}-\d{2}-\d{2}\.md$"#
        return path.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalized(_ markdown: String) -> String {
        let text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return text.hasSuffix("\n") ? text : text + "\n"
    }
}
