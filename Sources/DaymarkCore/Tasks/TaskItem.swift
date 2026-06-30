import Foundation

public struct TaskItem: Equatable, Sendable {
    public enum Status: String, Sendable {
        case open
        case completed
    }

    /// A due token parsed verbatim from the Markdown. Relative tokens (`today`,
    /// `tomorrow`) are kept as tokens, not resolved against a calendar; natural-language
    /// dates are intentionally not parsed yet. ISO dates are kept as written.
    public enum Due: Equatable, Sendable {
        case today
        case tomorrow
        case date(String)

        /// The token as it serializes for storage and display: `today`, `tomorrow`, or the ISO date.
        public var token: String {
            switch self {
            case .today: return "today"
            case .tomorrow: return "tomorrow"
            case .date(let iso): return iso
            }
        }

        /// Reconstructs a due value from its stored token, mirroring `token`.
        public init?(token: String) {
            switch token {
            case "today": self = .today
            case "tomorrow": self = .tomorrow
            default:
                guard TaskItem.isISODate(token) else { return nil }
                self = .date(token)
            }
        }
    }

    public var title: String
    public var status: Status
    public var tags: [String]
    public var mentions: [String]
    public var due: Due?

    // Source metadata. `notePath` is the workspace-relative path of the note the task came
    // from; it is empty when the parser is run on a bare string with no known source.
    public var notePath: String
    public var lineNumber: Int
    public var originalLine: String
    public var sectionHeading: String?

    public init(
        title: String,
        status: Status,
        tags: [String] = [],
        mentions: [String] = [],
        due: Due? = nil,
        notePath: String = "",
        lineNumber: Int = 0,
        originalLine: String = "",
        sectionHeading: String? = nil
    ) {
        self.title = title
        self.status = status
        self.tags = tags
        self.mentions = mentions
        self.due = due
        self.notePath = notePath
        self.lineNumber = lineNumber
        self.originalLine = originalLine
        self.sectionHeading = sectionHeading
    }

    /// A deterministic identity for a task, derived from its source location and text.
    /// Stable across reprojection so rollover can recognize a task it has already seen.
    public var sourceKey: String {
        let normalized = originalLine.trimmingCharacters(in: .whitespaces)
        return "\(notePath)\n\(lineNumber)\n\(normalized)"
    }

    /// True for a `yyyy-MM-dd` string that is also a real calendar date.
    static func isISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            return false
        }
        return ISODate.date(from: value) != nil
    }
}
