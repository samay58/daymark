import Foundation

public struct CodexContextBundle: Equatable, Sendable {
    public var title: String
    public var taskRelativePath: String
    public var goal: String
    public var sourcePath: String
    public var sourceLine: Int?
    public var sourceEndLine: Int?
    public var sourceBlock: String?
    public var sourceExcerpt: String
    public var constraints: [String]
    public var acceptanceCriteria: [String]
    public var suggestedFilePath: String

    public init(
        title: String,
        taskRelativePath: String,
        goal: String,
        sourcePath: String,
        sourceLine: Int? = nil,
        sourceEndLine: Int? = nil,
        sourceBlock: String? = nil,
        sourceExcerpt: String,
        constraints: [String] = [],
        acceptanceCriteria: [String],
        suggestedFilePath: String
    ) {
        self.title = title
        self.taskRelativePath = taskRelativePath
        self.goal = goal
        self.sourcePath = sourcePath
        self.sourceLine = sourceLine
        self.sourceEndLine = sourceEndLine
        self.sourceBlock = sourceBlock
        self.sourceExcerpt = sourceExcerpt
        self.constraints = constraints
        self.acceptanceCriteria = acceptanceCriteria
        self.suggestedFilePath = suggestedFilePath
    }

    public static func from(
        draft: CodexTaskDraft,
        taskRelativePath: String,
        date: Date,
        existingRelativePaths: Set<String>,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> CodexContextBundle {
        let preferredPath = suggestedRelativePath(title: draft.title, date: date, calendar: calendar)
        return CodexContextBundle(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            taskRelativePath: taskRelativePath.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePath: draft.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLine: draft.sourceLine,
            sourceEndLine: draft.sourceEndLine,
            sourceBlock: draft.sourceBlock,
            sourceExcerpt: draft.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            constraints: CodexTaskDraft.cleanedListItems(draft.constraints),
            acceptanceCriteria: CodexTaskDraft.cleanedListItems(draft.acceptanceCriteria),
            suggestedFilePath: CodexTaskDraft.collisionSafeRelativePath(
                preferredPath: preferredPath,
                existingRelativePaths: existingRelativePaths
            )
        )
    }

    public func markdown() -> String {
        var sections = [
            "# Context Bundle: \(CodexTaskDraft.clean(title))",
            """
            ## Task

            Task: `\(CodexTaskDraft.clean(taskRelativePath))`
            """,
            """
            ## Goal

            \(CodexTaskDraft.clean(goal))
            """,
            CodexTaskDraft.sourceSection(path: sourcePath, line: sourceLine, endLine: sourceEndLine, block: sourceBlock)
        ]

        if !CodexTaskDraft.clean(sourceExcerpt).isEmpty {
            sections.append("## Source Excerpt\n\n" + MarkdownCodeFence.wrap(CodexTaskDraft.clean(sourceExcerpt), info: "md"))
        }

        let cleanConstraints = CodexTaskDraft.cleanedListItems(constraints)
        if !cleanConstraints.isEmpty {
            sections.append("""
            ## Constraints

            \(cleanConstraints.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        let cleanCriteria = CodexTaskDraft.mergeCriteria(acceptanceCriteria, defaults: Self.acceptanceCriteriaDefaults)
            .map { "- [ ] \($0)" }.joined(separator: "\n")
        sections.append("""
        ## Acceptance Criteria

        \(cleanCriteria)
        """)

        if !CodexTaskDraft.clean(suggestedFilePath).isEmpty {
            sections.append("""
            ## Bundle File

            `\(CodexTaskDraft.clean(suggestedFilePath))`
            """)
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    public static func suggestedRelativePath(
        title: String,
        date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let datePrefix = ISODate.string(from: date, calendar: calendar)
        let slug = CodexTaskDraft.slugify(title)
        return "artifacts/context-bundles/\(datePrefix)-\(slug.isEmpty ? "codex-task" : slug)-context.md"
    }

    /// Whether the bundle has the content and valid paths required to write a file. The
    /// writer's validate() derives its granular errors from the same checks.
    public var isWritable: Bool {
        hasRequiredContent
            && CodexTaskDraft.isTaskPath(taskRelativePath)
            && Self.isBundlePath(suggestedFilePath)
    }

    public var hasRequiredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !taskRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isBundlePath(_ path: String) -> Bool {
        path.hasPrefix("artifacts/context-bundles/")
            && path.hasSuffix(".md")
            && !path.contains("..")
            && !path.hasPrefix("/")
    }

    public func withSuggestedFilePath(_ relativePath: String) -> CodexContextBundle {
        var copy = self
        copy.suggestedFilePath = relativePath
        return copy
    }

    /// Acceptance criteria that markdown() appends to every bundle file.
    static let acceptanceCriteriaDefaults = [
        "Source note remains unchanged",
        "Task file remains unchanged",
        "Bundle file is readable Markdown"
    ]

}

public struct CodexContextBundleWriteResult: Equatable, Sendable {
    public var relativePath: String
    public var url: URL

    public init(relativePath: String, url: URL) {
        self.relativePath = relativePath
        self.url = url
    }
}

public struct CodexContextBundleWriter {
    public enum Error: Swift.Error, Equatable {
        case blankBundle
        case invalidPath
    }

    private let fileManager: FileManager
    private let atomicWriter: AtomicFileWriter

    public init(fileManager: FileManager = .default, atomicWriter: AtomicFileWriter = AtomicFileWriter()) {
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
    }

    public func validate(_ bundle: CodexContextBundle) throws {
        guard bundle.hasRequiredContent else { throw Error.blankBundle }
        guard CodexTaskDraft.isTaskPath(bundle.taskRelativePath),
              CodexContextBundle.isBundlePath(bundle.suggestedFilePath) else {
            throw Error.invalidPath
        }
    }

    public func write(_ bundle: CodexContextBundle, root: WorkspaceRoot) throws -> CodexContextBundleWriteResult {
        try validate(bundle)
        let written = try writeCodexArtifact(
            preferredRelativePath: bundle.suggestedFilePath,
            directory: "artifacts/context-bundles",
            isValidPath: CodexContextBundle.isBundlePath,
            invalidPathError: { Error.invalidPath },
            makeMarkdown: { bundle.withSuggestedFilePath($0).markdown() },
            root: root,
            fileManager: fileManager,
            atomicWriter: atomicWriter
        )
        return CodexContextBundleWriteResult(relativePath: written.relativePath, url: written.url)
    }
}
