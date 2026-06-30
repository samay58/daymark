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
            sections.append("## Source Excerpt\n\n" + MarkdownCodeFence.wrap(clean(sourceExcerpt), info: "md"))
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

    /// Parses a task file produced by `markdown()` back into a draft. Fence-aware, so a
    /// Source Excerpt that contains `## ` headings or its own code fences round-trips
    /// verbatim. The parser lives beside the writer so the two formats cannot drift.
    /// `suggestedFilePath` is set to the file the draft was read from.
    public static func parse(taskMarkdown: String, taskRelativePath: String) -> CodexTaskDraft {
        let lines = normalizedLines(taskMarkdown)
        let sourceBody = sectionBodyLines("Source", in: lines).map { $0.trimmingCharacters(in: .whitespaces) }
        let range = sourceBody.compactMap { sourceLineRange(from: $0) }.first
        return CodexTaskDraft(
            title: documentTitle(in: lines),
            goal: sectionBodyLines("Goal", in: lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePath: sourceBody.compactMap { sourceValue(prefix: "Path:", line: $0) }.first ?? "",
            sourceLine: range?.start,
            sourceEndLine: range?.end,
            sourceBlock: sourceBody.compactMap { sourceValue(prefix: "Block:", line: $0) }.first,
            sourceExcerpt: fencedSectionBody("Source Excerpt", in: lines),
            constraints: cleanedListItems(sectionBodyLines("Constraints", in: lines)),
            suggestedFilePath: taskRelativePath,
            acceptanceCriteria: cleanedListItems(sectionBodyLines("Acceptance Criteria", in: lines))
        )
    }

    /// Whether the draft has the content and a valid task path required to write a file.
    /// `CodexTaskFileWriter.validate` derives its granular errors from the same checks, so
    /// the UI can ask for writability without constructing a writer.
    public var isWritable: Bool {
        hasRequiredContent && Self.isTaskPath(suggestedFilePath)
    }

    public var hasRequiredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isTaskPath(_ path: String) -> Bool {
        path.hasPrefix("specs/tasks/")
            && path.hasSuffix(".md")
            && !path.contains("..")
            && !path.hasPrefix("/")
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

    // MARK: - Parsing helpers (fence-aware, mirror the markdown() writer format)

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// The first level-1 heading outside any fenced code block.
    private static func documentTitle(in lines: [String]) -> String {
        var fence = MarkdownFenceScanner()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence.consume(trimmedLine: trimmed) { continue }
            if fence.isInsideFence { continue }
            if trimmed.hasPrefix("# "), !trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    /// Body lines of a top-level `## name` section. Fence-aware: a `## ` line inside a fenced
    /// code block neither starts nor ends a section, so an excerpt with headings is whole.
    private static func sectionBodyLines(_ name: String, in lines: [String]) -> [String] {
        let heading = "## \(name)"
        var fence = MarkdownFenceScanner()
        var collecting = false
        var body: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isDelimiter = fence.consume(trimmedLine: trimmed)
            let insideFence = fence.isInsideFence || isDelimiter
            if collecting {
                if !insideFence, trimmed.hasPrefix("## ") { break }
                body.append(line)
            } else if !insideFence, trimmed == heading {
                collecting = true
            }
        }
        return body
    }

    /// The content of the first fenced code block within a section (any fence length),
    /// trimmed. Falls back to the trimmed section body if no fence is present.
    private static func fencedSectionBody(_ name: String, in lines: [String]) -> String {
        let body = sectionBodyLines(name, in: lines)
        var fence = MarkdownFenceScanner()
        var capturing = false
        var sawFence = false
        var content: [String] = []
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence.consume(trimmedLine: trimmed) {
                if fence.isInsideFence {
                    capturing = true
                    sawFence = true
                } else {
                    break
                }
                continue
            }
            if capturing { content.append(line) }
        }
        let captured = sawFence ? content : body
        return captured.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceValue(prefix: String, line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("`"), raw.hasSuffix("`"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return raw.isEmpty ? nil : raw
    }

    private static func sourceLineRange(from line: String) -> (start: Int, end: Int?)? {
        if let value = sourceValue(prefix: "Line:", line: line), let number = Int(value) {
            return (number, nil)
        }
        guard let value = sourceValue(prefix: "Lines:", line: line) else { return nil }
        let parts = value.split(separator: "-", maxSplits: 1)
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        let end = parts.dropFirst().first.flatMap { Int($0) }
        return (start, end)
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
        guard draft.hasRequiredContent else { throw Error.blankDraft }
        guard CodexTaskDraft.isTaskPath(draft.suggestedFilePath) else { throw Error.invalidPath }
    }

    public func write(_ draft: CodexTaskDraft, root: WorkspaceRoot) throws -> CodexTaskWriteResult {
        try validate(draft)
        let relativePath = collisionSafePath(preferredPath: draft.suggestedFilePath, root: root)
        guard CodexTaskDraft.isTaskPath(relativePath) else { throw Error.invalidPath }
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
}
