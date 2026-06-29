import Foundation
import DaymarkCore
import DaymarkStore

public struct TaskRolloverRun: Equatable, Sendable {
    public var targetNotePath: String
    public var entries: [RolloverEntry]
    public var applied: Bool

    public init(targetNotePath: String, entries: [RolloverEntry], applied: Bool) {
        self.targetNotePath = targetNotePath
        self.entries = entries
        self.applied = applied
    }
}

public struct TaskRolloverEngine {
    public let root: WorkspaceRoot
    public let database: Database
    public let calendar: Calendar

    public init(root: WorkspaceRoot, database: Database, calendar: Calendar = .current) {
        self.root = root
        self.database = database
        self.calendar = calendar
    }

    public func run(date: Date = Date(), apply: Bool) async throws -> TaskRolloverRun {
        try WorkspaceBootstrapper().bootstrap(root: root)

        let store = DailyNoteStore(root: root, calendar: calendar)
        _ = try store.ensureTodayNote(date: date)
        let targetPath = DailyNote.relativePath(for: date, calendar: calendar)

        let indexer = WorkspaceIndexer(root: root, database: database, calendar: calendar)
        _ = try await indexer.rebuild()

        let tasks = try await database.openTasks()
        let todayMarkdown = try store.loadToday(date: date)
        let plan = TaskRollover.plan(tasks: tasks, todayMarkdown: todayMarkdown, todayPath: targetPath)

        guard apply, !plan.entries.isEmpty else {
            return TaskRolloverRun(targetNotePath: targetPath, entries: plan.entries, applied: false)
        }

        try store.save(plan.updatedMarkdown, date: date)
        for entry in plan.entries {
            _ = try await database.recordRollover(RolloverRecord(
                sourceKey: entry.task.sourceKey,
                sourceNotePath: entry.task.notePath,
                sourceLineNumber: entry.task.lineNumber,
                sourceTitle: entry.task.title,
                targetNotePath: targetPath,
                marker: entry.marker
            ))
        }
        try await indexer.indexToday(date: date)
        return TaskRolloverRun(targetNotePath: targetPath, entries: plan.entries, applied: true)
    }
}
