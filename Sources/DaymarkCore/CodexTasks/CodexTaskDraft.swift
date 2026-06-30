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
            "# \(Self.clean(title))",
            """
            ## Goal

            \(Self.clean(goal))
            """,
            Self.sourceSection(path: sourcePath, line: sourceLine, endLine: sourceEndLine, block: sourceBlock)
        ]

        if !Self.clean(sourceExcerpt).isEmpty {
            sections.append("## Source Excerpt\n\n" + MarkdownCodeFence.wrap(Self.clean(sourceExcerpt), info: "md"))
        }

        let cleanConstraints = constraints.map(Self.clean).filter { !$0.isEmpty }
        if !cleanConstraints.isEmpty {
            sections.append("""
            ## Constraints

            \(cleanConstraints.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        let criteria = Self.mergeCriteria(acceptanceCriteria, defaults: Self.acceptanceCriteriaDefaults)
            .map { "- [ ] \($0)" }.joined(separator: "\n")
        sections.append("""
        ## Acceptance Criteria

        \(criteria)
        """)

        if !Self.clean(suggestedFilePath).isEmpty {
            sections.append("""
            ## Suggested File

            `\(Self.clean(suggestedFilePath))`
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
            acceptanceCriteria: userAcceptanceCriteria(in: lines)
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
        let cleanedTitle = Self.clean(title)
        let preferredPath = Self.suggestedRelativePath(title: cleanedTitle, date: date, calendar: calendar)
        var copy = self
        copy.title = cleanedTitle
        copy.goal = Self.clean(goal)
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

    /// Acceptance criteria as the user authored them, with the defaults markdown() injects
    /// filtered back out so parse(markdown()) does not promote a default to user content.
    private static func userAcceptanceCriteria(in lines: [String]) -> [String] {
        let defaults = Set(acceptanceCriteriaDefaults.map { $0.lowercased() })
        return cleanedListItems(sectionBodyLines("Acceptance Criteria", in: lines))
            .filter { !defaults.contains($0.lowercased()) }
    }

    public static func suggestedRelativePath(
        title: String,
        date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let datePrefix = ISODate.string(from: date, calendar: calendar)
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

    /// The `## Source` section shared by the task file and the context bundle. Static so both
    /// types render it from identical code.
    static func sourceSection(path: String, line: Int?, endLine: Int?, block: String?) -> String {
        var lines = ["Path: `\(clean(path))`"]
        if let line {
            if let endLine, endLine > line {
                lines.append("Lines: \(line)-\(endLine)")
            } else {
                lines.append("Line: \(line)")
            }
        }
        if let block = block.map(clean), !block.isEmpty {
            lines.append("Block: \(block)")
        }
        return """
        ## Source

        \(lines.joined(separator: "\n"))
        """
    }

    /// Acceptance criteria that markdown() appends to every task file. Kept as one constant
    /// so parse() can strip them back out and the round-trip stays lossless.
    static let acceptanceCriteriaDefaults = ["Source note remains unchanged", "Task file is readable Markdown"]

    /// User criteria plus the given defaults, cleaned and de-duplicated case-insensitively.
    /// Shared so the task file and the context bundle merge criteria identically.
    static func mergeCriteria(_ criteria: [String], defaults: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for criterion in criteria + defaults {
            let cleaned = clean(criterion)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            if seen.insert(key).inserted {
                output.append(cleaned)
            }
        }
        return output
    }

    static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing helpers (fence-aware, mirror the markdown() writer format)

    private static func normalizedLines(_ text: String) -> [String] {
        text.normalizedNewlines.components(separatedBy: "\n")
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

}

public struct CodexTaskWriteResult: Equatable, Sendable {
    public var relativePath: String
    public var url: URL

    public init(relativePath: String, url: URL) {
        self.relativePath = relativePath
        self.url = url
    }
}

/// Resolves a collision-safe path under `directory`, validates it, and atomically writes a
/// Codex artifact. `makeMarkdown` is invoked with the FINAL relative path AFTER collision
/// resolution, so the path embedded in the file body matches the filename actually written;
/// passing a pre-built String would embed the pre-collision path on a name collision. Each
/// writer keeps its own validate(), typed Error, and result struct.
func writeCodexArtifact(
    preferredRelativePath: String,
    directory: String,
    isValidPath: (String) -> Bool,
    invalidPathError: () -> Swift.Error,
    makeMarkdown: (String) -> String,
    root: WorkspaceRoot,
    fileManager: FileManager,
    atomicWriter: AtomicFileWriter
) throws -> (relativePath: String, url: URL) {
    let relativePath = CodexTaskDraft.collisionSafeRelativePath(
        preferredPath: preferredRelativePath,
        existingRelativePaths: root.existingMarkdownRelativePaths(under: directory, fileManager: fileManager)
    )
    guard isValidPath(relativePath) else { throw invalidPathError() }
    let fileURL = root.expandedURL.appendingPathComponent(relativePath)
    try atomicWriter.write(makeMarkdown(relativePath), to: fileURL, fileManager: fileManager)
    return (relativePath, fileURL)
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
        let written = try writeCodexArtifact(
            preferredRelativePath: draft.suggestedFilePath,
            directory: "specs/tasks",
            isValidPath: CodexTaskDraft.isTaskPath,
            invalidPathError: { Error.invalidPath },
            makeMarkdown: { draft.withSuggestedFilePath($0).markdown() },
            root: root,
            fileManager: fileManager,
            atomicWriter: atomicWriter
        )
        return CodexTaskWriteResult(relativePath: written.relativePath, url: written.url)
    }
}
