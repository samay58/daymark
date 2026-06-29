import Foundation

/// A bucket on the Open Loops surface. Dated tasks are grouped by when they are due;
/// undated tasks split by whether they are waiting on someone else.
public enum OpenLoopBucket: String, Sendable, CaseIterable {
    case dueToday
    case overdue
    case upcoming
    case waitingOnOthers
    case noDate

    public var title: String {
        switch self {
        case .dueToday: return "Due today"
        case .overdue: return "Overdue"
        case .upcoming: return "Upcoming"
        case .waitingOnOthers: return "Waiting on others"
        case .noDate: return "No date"
        }
    }
}

public struct OpenLoopGroup: Equatable, Sendable {
    public var bucket: OpenLoopBucket
    public var tasks: [TaskItem]

    public init(bucket: OpenLoopBucket, tasks: [TaskItem]) {
        self.bucket = bucket
        self.tasks = tasks
    }
}

public enum OpenLoops {
    /// Groups open tasks for the Open Loops surface. Completed tasks are excluded. Each task
    /// lands in exactly one bucket, input order is preserved within a bucket, and empty
    /// buckets are omitted. `referenceDate` resolves ISO due dates into due-today, overdue,
    /// or upcoming; the relative tokens `today` and `tomorrow` are taken at face value rather
    /// than recomputed against the note's own date (natural-language dates are not resolved yet).
    public static func grouped(
        tasks: [TaskItem],
        on referenceDate: Date,
        calendar: Calendar = .current
    ) -> [OpenLoopGroup] {
        let referenceISO = isoString(for: referenceDate, calendar: calendar)
        var byBucket: [OpenLoopBucket: [TaskItem]] = [:]

        for task in tasks where task.status == .open {
            byBucket[bucket(for: task, referenceISO: referenceISO), default: []].append(task)
        }

        return OpenLoopBucket.allCases.compactMap { bucket in
            guard let tasks = byBucket[bucket], !tasks.isEmpty else { return nil }
            return OpenLoopGroup(bucket: bucket, tasks: tasks)
        }
    }

    private static func bucket(for task: TaskItem, referenceISO: String) -> OpenLoopBucket {
        switch task.due {
        case .today:
            return .dueToday
        case .tomorrow:
            return .upcoming
        case .date(let iso):
            if iso == referenceISO { return .dueToday }
            return iso < referenceISO ? .overdue : .upcoming
        case nil:
            return isWaiting(task) ? .waitingOnOthers : .noDate
        }
    }

    /// An undated task is "waiting on others" when it names someone (`@mention`) or carries
    /// an explicit `waiting:` marker. Without such a marker we do not guess.
    private static func isWaiting(_ task: TaskItem) -> Bool {
        if !task.mentions.isEmpty { return true }
        return task.title.lowercased().contains("waiting:")
    }

    private static func isoString(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
