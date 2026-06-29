import Foundation

/// Reads and writes the daily Markdown note on disk. Markdown is the source of truth;
/// this type never touches SQLite.
public struct DailyNoteStore {
    public let root: WorkspaceRoot
    public let calendar: Calendar
    private let writer = AtomicFileWriter()
    public static let captureSectionHeading = "## Capture"

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

    /// Appends a timestamped capture bullet under today's `## Capture` section, creating the
    /// note from the template first when missing. Existing content is preserved.
    @discardableResult
    public func appendCapture(
        _ text: String,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureError.empty }
        let bullet = CaptureFormatter.timestampedBullet(trimmed, at: date, calendar: calendar)
        return try appendEntry(bullet, date: date, fileManager: fileManager)
    }

    /// Appends an open Markdown task line under today's `## Capture` section, creating the
    /// note from the template first when missing. Existing content is preserved.
    @discardableResult
    public func appendTask(
        _ text: String,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureError.empty }
        let line = CaptureFormatter.taskLine(trimmed)
        return try appendEntry(line, date: date, fileManager: fileManager)
    }

    private func appendEntry(_ entry: String, date: Date, fileManager: FileManager) throws -> URL {
        _ = try ensureTodayNote(date: date, fileManager: fileManager)
        let url = todayFileURL(date: date)
        let existing = try String(contentsOf: url, encoding: .utf8)
        let updated = MarkdownSection.appendingEntry(entry, under: Self.captureSectionHeading, to: existing)
        try writer.write(updated, to: url, fileManager: fileManager)
        return url
    }
}
