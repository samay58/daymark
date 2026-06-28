import Foundation

public struct DailyNote: Equatable, Sendable {
    public var date: Date
    public var markdown: String

    public init(date: Date, markdown: String) {
        self.date = date
        self.markdown = markdown
    }

    /// The note's path relative to the workspace root, as `daily/YYYY/MM/YYYY-MM-DD.md`.
    public static func relativePath(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "daily/%04d/%02d/%04d-%02d-%02d.md", year, month, year, month, day)
    }

    public static func fileURL(in root: WorkspaceRoot, for date: Date, calendar: Calendar = .current) -> URL {
        root.expandedURL.appendingPathComponent(relativePath(for: date, calendar: calendar))
    }

    /// A minimal, readable Markdown template for a new daily note.
    public static func defaultTemplate(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        let title = formatter.string(from: date)
        return """
        # \(title)

        ## Brief

        ## Capture

        ## Decisions

        ## End of day

        """
    }

    public static let sampleMarkdown = """
    # 2026-06-28

    ## Plan for today

    - Ship the Daymark repository scaffold
    - Keep the editor quiet and central
    - Save mockups into the project

    ## Focus

    - [x] Create governance docs
    - [ ] Verify build and tests
    - [ ] Start taste prototype

    ## Notes

    Daymark should feel useful before AI. The writing surface is the product.
    """
}
