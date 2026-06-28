import Foundation

/// Reads and writes the daily Markdown note on disk. Markdown is the source of truth;
/// this type never touches SQLite.
public struct DailyNoteStore {
    public let root: WorkspaceRoot
    public let calendar: Calendar
    private let writer = AtomicFileWriter()

    public init(root: WorkspaceRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    public func todayFileURL(date: Date = Date()) -> URL {
        DailyNote.fileURL(in: root, for: date, calendar: calendar)
    }

    /// Ensures today's note exists, creating it from the default template only when missing.
    /// Existing notes are never overwritten.
    @discardableResult
    public func ensureTodayNote(
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> (url: URL, created: Bool) {
        let url = todayFileURL(date: date)
        if fileManager.fileExists(atPath: url.path) {
            return (url, false)
        }
        try writer.write(DailyNote.defaultTemplate(for: date, calendar: calendar), to: url)
        return (url, true)
    }

    public func loadToday(date: Date = Date()) throws -> String {
        try String(contentsOf: todayFileURL(date: date), encoding: .utf8)
    }

    public func save(_ markdown: String, date: Date = Date()) throws {
        try writer.write(markdown, to: todayFileURL(date: date))
    }
}
