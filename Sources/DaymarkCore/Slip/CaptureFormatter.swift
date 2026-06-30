import Foundation

/// Formats a capture's plain text into readable Markdown lines. A capture is trimmed,
/// blank lines are dropped, and continuations are indented so a multiline capture stays a
/// single readable list item.
public enum CaptureFormatter {
    public static func timestamp(for date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar: calendar, format: "HH:mm").string(from: date)
    }

    public static func dayHeading(for date: Date, calendar: Calendar = .current) -> String {
        "## " + ISODate.string(from: date, calendar: calendar)
    }

    /// A timestamped slip/capture bullet, for example `- 09:30 buy milk`.
    public static func timestampedBullet(_ text: String, at date: Date, calendar: Calendar = .current) -> String {
        bullet(marker: "- \(timestamp(for: date, calendar: calendar)) ", text: text)
    }

    /// An open Markdown task line, for example `- [ ] write the spec`.
    public static func taskLine(_ text: String) -> String {
        bullet(marker: "- [ ] ", text: text)
    }

    // MARK: - Helpers

    private static func bullet(marker: String, text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return marker.trimmingCharacters(in: .whitespaces) }
        let continuations = lines.dropFirst().map { "  \($0)" }
        return ([marker + first] + continuations).joined(separator: "\n")
    }

    private static func formatter(calendar: Calendar, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
