import Foundation

public struct MeetingEventSnapshot: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case missingTitle
        case invalidDate(String)

        public var errorDescription: String? {
            switch self {
            case .missingTitle:
                return "meeting event title is required"
            case .invalidDate(let value):
                return "invalid meeting event date: \(value)"
            }
        }
    }

    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var location: String?
    public var attendees: [String]
    public var tags: [String]
    public var notes: String
    public var sourceIdentifier: String?

    public init(
        title: String,
        startsAt: Date,
        endsAt: Date,
        location: String? = nil,
        attendees: [String] = [],
        tags: [String] = [],
        notes: String = "",
        sourceIdentifier: String? = nil
    ) {
        self.title = Self.clean(title)
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = Self.optionalClean(location)
        self.attendees = attendees.map(Self.clean).filter { !$0.isEmpty }
        self.tags = tags.map(Self.clean).filter { $0.hasPrefix("#") && $0.count > 1 }.sorted()
        self.notes = Self.clean(notes)
        self.sourceIdentifier = Self.optionalClean(sourceIdentifier)
    }

    public static func decode(data: Data, sourceIdentifier: String?) throws -> MeetingEventSnapshot {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let title = clean(raw.title)
        guard !title.isEmpty else { throw Error.missingTitle }
        let startsAt = try parseDate(raw.startsAt)
        let endsAt = try parseDate(raw.endsAt)
        return MeetingEventSnapshot(
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            location: raw.location,
            attendees: raw.attendees ?? [],
            tags: raw.tags ?? [],
            notes: raw.notes ?? "",
            sourceIdentifier: sourceIdentifier
        )
    }

    private struct Raw: Decodable {
        var title: String
        var startsAt: String
        var endsAt: String
        var location: String?
        var attendees: [String]?
        var tags: [String]?
        var notes: String?
    }

    private static func parseDate(_ value: String) throws -> Date {
        if let date = isoDateFormatter.date(from: value) { return date }
        if let date = isoDateFormatterWithFractionalSeconds.date(from: value) { return date }
        throw Error.invalidDate(value)
    }

    private static let isoDateFormatter = ISO8601DateFormatter()

    private static let isoDateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optionalClean(_ value: String?) -> String? {
        guard let cleaned = value.map(clean), !cleaned.isEmpty else { return nil }
        return cleaned
    }
}

public struct MeetingPrepSource: Equatable, Sendable {
    public var title: String
    public var relativePath: String
    public var tags: [String]

    public init(title: String, relativePath: String, tags: [String]) {
        self.title = title
        self.relativePath = relativePath
        self.tags = tags
    }
}

public struct MeetingPrepQuestion: Equatable, Sendable {
    public var text: String
    public var relativePath: String
    public var lineNumber: Int

    public init(text: String, relativePath: String, lineNumber: Int) {
        self.text = text
        self.relativePath = relativePath
        self.lineNumber = lineNumber
    }
}

public struct MeetingPrepContext: Equatable, Sendable {
    public var sources: [MeetingPrepSource]
    public var openTasks: [TaskItem]
    public var codexArtifacts: [DynamicBlockCodexContextArtifact]
    public var questions: [MeetingPrepQuestion]

    public init(
        sources: [MeetingPrepSource],
        openTasks: [TaskItem],
        codexArtifacts: [DynamicBlockCodexContextArtifact],
        questions: [MeetingPrepQuestion]
    ) {
        self.sources = sources
        self.openTasks = openTasks
        self.codexArtifacts = codexArtifacts
        self.questions = questions
    }

    public static let empty = MeetingPrepContext(
        sources: [],
        openTasks: [],
        codexArtifacts: [],
        questions: []
    )
}

public struct MeetingPrepDraft: Equatable, Sendable {
    public var event: MeetingEventSnapshot
    public var context: MeetingPrepContext
    public var suggestedFilePath: String

    public init(event: MeetingEventSnapshot, context: MeetingPrepContext, suggestedFilePath: String) {
        self.event = event
        self.context = context
        self.suggestedFilePath = suggestedFilePath
    }

    public func markdown() -> String {
        var sections: [String] = [
            "# Meeting Prep: \(MeetingEventSnapshot.clean(event.title))",
            metadataSection(),
            whySection(),
            localContextSection(),
            openLoopsSection(),
            codexHandoffsSection(),
            questionsSection()
        ]

        if !suggestedFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("""
            ## Prep File

            `\(suggestedFilePath)`
            """)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    public var isWritable: Bool {
        !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isMeetingPath(suggestedFilePath)
            && !markdown().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isMeetingPath(_ path: String) -> Bool {
        path.hasPrefix("meetings/")
            && path.hasSuffix(".md")
            && !path.contains("..")
            && !path.hasPrefix("/")
    }

    public static func suggestedRelativePath(
        title: String,
        date: Date,
        existingRelativePaths: Set<String>,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let datePrefix = ISODate.string(from: date, calendar: calendar)
        let slug = CodexTaskDraft.slugify(title)
        let preferred = "meetings/\(datePrefix)-\(slug.isEmpty ? "meeting-prep" : slug).md"
        return CodexTaskDraft.collisionSafeRelativePath(
            preferredPath: preferred,
            existingRelativePaths: existingRelativePaths
        )
    }

    private func metadataSection() -> String {
        var lines = [
            "Time: \(Self.timeString(event.startsAt))",
            "Attendees: \(event.attendees.isEmpty ? "None listed" : event.attendees.joined(separator: ", "))"
        ]
        if let location = event.location {
            lines.append("Location: \(location)")
        }
        if !event.tags.isEmpty {
            lines.append("Tags: \(event.tags.joined(separator: ", "))")
        }
        if let source = event.sourceIdentifier {
            lines.append("Source event: `\(source)`")
        }
        return lines.joined(separator: "\n")
    }

    private func whySection() -> String {
        let note = event.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = note.isEmpty ? event.title : note
        return """
        ## Why This Meeting Exists

        - \(reason)
        """
    }

    private func localContextSection() -> String {
        guard !context.sources.isEmpty else {
            let target = event.tags.isEmpty ? "this meeting" : event.tags.joined(separator: ", ")
            return """
            ## Local Context

            No local context found for \(target).
            """
        }

        return """
        ## Local Context

        \(context.sources.map { "- Source: \($0.title) (`\($0.relativePath)`)" }.joined(separator: "\n"))
        """
    }

    private func openLoopsSection() -> String {
        guard !context.openTasks.isEmpty else {
            return """
            ## Open Loops

            No open loops found.
            """
        }

        let lines = context.openTasks.map { task in
            "- [ ] \(task.title) (`\(task.notePath):\(task.lineNumber)`)"
        }
        return """
        ## Open Loops

        \(lines.joined(separator: "\n"))
        """
    }

    private func codexHandoffsSection() -> String {
        guard !context.codexArtifacts.isEmpty else {
            return """
            ## Codex Handoffs

            No Codex handoffs found.
            """
        }

        let lines = context.codexArtifacts.map { artifact in
            "- \(artifactLabel(artifact.kind)): \(artifact.title) (`\(artifact.relativePath)`)"
        }
        return """
        ## Codex Handoffs

        \(lines.joined(separator: "\n"))
        """
    }

    private func questionsSection() -> String {
        guard !context.questions.isEmpty else {
            return """
            ## Questions To Carry In

            No unresolved questions found.
            """
        }

        let lines = context.questions.map { question in
            "- \(question.text) (`\(question.relativePath):\(question.lineNumber)`)"
        }
        return """
        ## Questions To Carry In

        \(lines.joined(separator: "\n"))
        """
    }

    private func artifactLabel(_ kind: DynamicBlockCodexContextKind) -> String {
        switch kind {
        case .taskSpec: return "Task spec"
        case .contextBundle: return "Context bundle"
        }
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        return formatter.string(from: date)
    }
}

public struct MeetingPrepWriteResult: Equatable, Sendable {
    public var relativePath: String
    public var url: URL

    public init(relativePath: String, url: URL) {
        self.relativePath = relativePath
        self.url = url
    }
}

public struct MeetingPrepWriter {
    public enum Error: Swift.Error, Equatable {
        case blankDraft
        case invalidPath
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validate(_ draft: MeetingPrepDraft) throws {
        guard !draft.event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.markdown().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.blankDraft
        }
        guard MeetingPrepDraft.isMeetingPath(draft.suggestedFilePath) else {
            throw Error.invalidPath
        }
    }

    public func write(_ draft: MeetingPrepDraft, root: WorkspaceRoot) throws -> MeetingPrepWriteResult {
        try validate(draft)
        let relativePath = MeetingPrepDraft.suggestedRelativePath(
            title: draft.event.title,
            date: draft.event.startsAt,
            existingRelativePaths: root.existingMarkdownRelativePaths(under: "meetings", fileManager: fileManager)
        )
        let finalDraft = MeetingPrepDraft(
            event: draft.event,
            context: draft.context,
            suggestedFilePath: relativePath
        )
        let url = root.expandedURL.appendingPathComponent(relativePath)
        try AtomicFileWriter().write(finalDraft.markdown(), to: url, fileManager: fileManager)
        return MeetingPrepWriteResult(relativePath: relativePath, url: url)
    }
}
