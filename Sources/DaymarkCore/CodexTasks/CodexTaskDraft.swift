import Foundation

public struct CodexTaskDraft: Equatable, Sendable {
    public var title: String
    public var goal: String
    public var sourcePath: String
    public var sourceLine: Int?
    public var sourceEndLine: Int?
    public var sourceBlock: String?
    public var sourceExcerpt: String
    public var constraints: [String]
    public var suggestedFilePath: String
    public var acceptanceCriteria: [String]

    public init(
        title: String,
        goal: String,
        sourcePath: String,
        sourceLine: Int? = nil,
        sourceEndLine: Int? = nil,
        sourceBlock: String? = nil,
        sourceExcerpt: String = "",
        constraints: [String] = [],
        suggestedFilePath: String = "",
        acceptanceCriteria: [String]
    ) {
        self.title = title
        self.goal = goal
        self.sourcePath = sourcePath
        self.sourceLine = sourceLine
        self.sourceEndLine = sourceEndLine
        self.sourceBlock = sourceBlock
        self.sourceExcerpt = sourceExcerpt
        self.constraints = constraints
        self.suggestedFilePath = suggestedFilePath
        self.acceptanceCriteria = acceptanceCriteria
    }

    public func markdown() -> String {
        var sections = [
            "# \(clean(title))",
            """
            ## Goal

            \(clean(goal))
            """,
            sourceSection()
        ]

        if !clean(sourceExcerpt).isEmpty {
            sections.append("""
            ## Source Excerpt

            ```md
            \(clean(sourceExcerpt))
            ```
            """)
        }

        let cleanConstraints = constraints.map(clean).filter { !$0.isEmpty }
        if !cleanConstraints.isEmpty {
            sections.append("""
            ## Constraints

            \(cleanConstraints.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        let criteria = mergedCriteria().map { "- [ ] \($0)" }.joined(separator: "\n")
        sections.append("""
        ## Acceptance Criteria

        \(criteria)
        """)

        if !clean(suggestedFilePath).isEmpty {
            sections.append("""
            ## Suggested File

            `\(clean(suggestedFilePath))`
            """)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    public func withSuggestedFilePath(_ relativePath: String) -> CodexTaskDraft {
        var copy = self
        copy.suggestedFilePath = relativePath
        return copy
    }

    public func withEditedFields(
        title: String,
        goal: String,
        constraints: [String],
        acceptanceCriteria: [String],
        date: Date,
        existingRelativePaths: Set<String>,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> CodexTaskDraft {
        let cleanedTitle = clean(title)
        let preferredPath = Self.suggestedRelativePath(title: cleanedTitle, date: date, calendar: calendar)
        var copy = self
        copy.title = cleanedTitle
        copy.goal = clean(goal)
        copy.constraints = Self.cleanedListItems(constraints)
        copy.acceptanceCriteria = Self.cleanedListItems(acceptanceCriteria)
        copy.suggestedFilePath = Self.collisionSafeRelativePath(
            preferredPath: preferredPath,
            existingRelativePaths: existingRelativePaths
        )
        return copy
    }

    public static func cleanedListItems(_ values: [String]) -> [String] {
        values.compactMap { value in
            let cleaned = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"^\s*[-*+]\s+"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    public static func suggestedRelativePath(
        title: String,
        date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let datePrefix = dateFormatter(calendar: calendar).string(from: date)
        let slug = slugify(title)
        return "specs/tasks/\(datePrefix)-\(slug.isEmpty ? "codex-task" : slug).md"
    }

    public static func collisionSafeRelativePath(
        preferredPath: String,
        existingRelativePaths: Set<String>
    ) -> String {
        guard existingRelativePaths.contains(preferredPath) else { return preferredPath }
        let url = URL(fileURLWithPath: preferredPath)
        let directory = url.deletingLastPathComponent().relativePath
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        var index = 2
        while true {
            let candidate = "\(directory)/\(base)-\(index).\(ext)"
            if !existingRelativePaths.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    public static func slugify(_ value: String) -> String {
        let lower = value.lowercased()
        var output = ""
        var previousWasSeparator = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("-")
                previousWasSeparator = true
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func sourceSection() -> String {
        var lines = ["Path: `\(clean(sourcePath))`"]
        if let sourceLine {
            if let sourceEndLine, sourceEndLine > sourceLine {
                lines.append("Lines: \(sourceLine)-\(sourceEndLine)")
            } else {
                lines.append("Line: \(sourceLine)")
            }
        }
        if let sourceBlock = sourceBlock.map(clean), !sourceBlock.isEmpty {
            lines.append("Block: \(sourceBlock)")
        }
        return """
        ## Source

        \(lines.joined(separator: "\n"))
        """
    }

    private func mergedCriteria() -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        let defaults = ["Source note remains unchanged", "Task file is readable Markdown"]
        for criterion in acceptanceCriteria + defaults {
            let cleaned = clean(criterion)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            if seen.insert(key).inserted {
                output.append(cleaned)
            }
        }
        return output
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

public struct CodexTaskWriteResult: Equatable, Sendable {
    public var relativePath: String
    public var url: URL

    public init(relativePath: String, url: URL) {
        self.relativePath = relativePath
        self.url = url
    }
}

public struct CodexTaskFileWriter {
    public enum Error: Swift.Error, Equatable {
        case blankDraft
        case invalidPath
    }

    private let fileManager: FileManager
    private let atomicWriter: AtomicFileWriter

    public init(fileManager: FileManager = .default, atomicWriter: AtomicFileWriter = AtomicFileWriter()) {
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
    }

    public func validate(_ draft: CodexTaskDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.blankDraft
        }
        guard isTaskPath(draft.suggestedFilePath) else {
            throw Error.invalidPath
        }
    }

    public func write(_ draft: CodexTaskDraft, root: WorkspaceRoot) throws -> CodexTaskWriteResult {
        try validate(draft)
        let relativePath = collisionSafePath(preferredPath: draft.suggestedFilePath, root: root)
        guard isTaskPath(relativePath) else { throw Error.invalidPath }
        let fileURL = root.expandedURL.appendingPathComponent(relativePath)
        let finalDraft = draft.withSuggestedFilePath(relativePath)
        try atomicWriter.write(finalDraft.markdown(), to: fileURL, fileManager: fileManager)
        return CodexTaskWriteResult(relativePath: relativePath, url: fileURL)
    }

    private func collisionSafePath(preferredPath: String, root: WorkspaceRoot) -> String {
        CodexTaskDraft.collisionSafeRelativePath(
            preferredPath: preferredPath,
            existingRelativePaths: root.existingMarkdownRelativePaths(under: "specs/tasks", fileManager: fileManager)
        )
    }

    private func isTaskPath(_ path: String) -> Bool {
        path.hasPrefix("specs/tasks/")
            && path.hasSuffix(".md")
            && !path.contains("..")
            && !path.hasPrefix("/")
    }
}
