import Foundation

/// Raised when a capture has no content after trimming. Nothing is written.
public enum CaptureError: Error, Equatable {
    case empty
}

/// Writes captures to the readable monthly Slip Markdown file at `slip/YYYY-MM.md`.
/// Markdown is the source of truth; this type never touches SQLite. Writes are atomic.
public struct SlipStore {
    public let root: WorkspaceRoot
    public let calendar: Calendar
    private let writer = AtomicFileWriter()

    public init(root: WorkspaceRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    public func monthlyRelativePath(for date: Date = Date()) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        return String(format: "slip/%04d-%02d.md", year, month)
    }

    public func monthlyFileURL(for date: Date = Date()) -> URL {
        root.expandedURL.appendingPathComponent(monthlyRelativePath(for: date))
    }

    /// Appends a timestamped bullet under the day's heading in this month's Slip file,
    /// creating the file when missing. Throws `CaptureError.empty` and writes nothing for
    /// blank captures.
    @discardableResult
    public func save(_ text: String, date: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureError.empty }

        let url = monthlyFileURL(for: date)
        let existing: String
        if fileManager.fileExists(atPath: url.path) {
            // Read with `try`, not `try?`: if an existing slip file cannot be read, propagate
            // the error rather than silently overwriting a month of captures with a fresh file.
            let onDisk = try String(contentsOf: url, encoding: .utf8)
            existing = onDisk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? newMonthlyDocument(for: date)
                : onDisk
        } else {
            existing = newMonthlyDocument(for: date)
        }
        let bullet = CaptureFormatter.timestampedBullet(trimmed, at: date, calendar: calendar)
        let heading = CaptureFormatter.dayHeading(for: date, calendar: calendar)
        let updated = MarkdownSection.appendingEntry(bullet, under: heading, to: existing)
        try writer.write(updated, to: url, fileManager: fileManager)
        return url
    }

    private func newMonthlyDocument(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return "# Slip \(formatter.string(from: date))\n"
    }
}
