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
            let prefix = humanizedPrefix(sourcePath: task.notePath, targetPath: todayPath)
            let line = "- \(prefix) \(task.title) (from \(source)) \(marker)"
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

    /// The human-facing prefix for a rollover line, derived entirely from the source and
    /// target note dates so output stays deterministic regardless of wall-clock time.
    static func humanizedPrefix(sourcePath: String, targetPath: String) -> String {
        guard let sourceDate = dailyNoteDate(from: sourcePath),
              let targetDate = dailyNoteDate(from: targetPath) else {
            return "From \(sourcePath):"
        }

        let calendar = dateMathCalendar
        let dayCount = calendar.dateComponents([.day], from: sourceDate, to: targetDate).day ?? 0

        if dayCount == 1 {
            return "From yesterday:"
        }
        if dayCount >= 2, dayCount <= 6 {
            return "From \(weekdayFormatter.string(from: sourceDate)):"
        }
        return "From \(monthDayFormatter.string(from: sourceDate)):"
    }

    private static let dateMathCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        return calendar
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = dateMathCalendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = dateMathCalendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Parses `daily/YYYY/MM/YYYY-MM-DD.md` into a UTC midnight `Date`. Returns `nil` for
    /// anything that does not match the daily note path shape.
    private static func dailyNoteDate(from path: String) -> Date? {
        let pattern = #"^daily/(\d{4})/(\d{2})/(\d{4})-(\d{2})-(\d{2})\.md$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let yearRange = Range(match.range(at: 3), in: path),
              let monthRange = Range(match.range(at: 4), in: path),
              let dayRange = Range(match.range(at: 5), in: path),
              let year = Int(path[yearRange]),
              let month = Int(path[monthRange]),
              let day = Int(path[dayRange]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return dateMathCalendar.date(from: components)
    }

    private static func normalized(_ markdown: String) -> String {
        let text = markdown.normalizedNewlines
        return text.hasSuffix("\n") ? text : text + "\n"
    }
}
