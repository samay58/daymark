import Foundation
import DaymarkCore

public struct DynamicBlockRefreshPreview: Equatable, Sendable {
    public var sourcePath: String
    public var sourceContentHash: String
    public var plan: DynamicBlockPatchPlan

    public init(sourcePath: String, sourceContentHash: String, plan: DynamicBlockPatchPlan) {
        self.sourcePath = sourcePath
        self.sourceContentHash = sourceContentHash
        self.plan = plan
    }
}

public struct DynamicBlockRefreshApplyResult: Equatable, Sendable {
    public var updatedMarkdown: String
    public var cacheWarning: String?

    public init(updatedMarkdown: String, cacheWarning: String? = nil) {
        self.updatedMarkdown = updatedMarkdown
        self.cacheWarning = cacheWarning
    }
}

public enum DynamicBlockRefreshError: LocalizedError, Equatable {
    case sourceOutsideWorkspace(String)
    case stalePreview

    public var errorDescription: String? {
        switch self {
        case .sourceOutsideWorkspace(let path):
            return "dynamic block source is outside the workspace: \(path)"
        case .stalePreview:
            return "dynamic block preview is stale; preview again before applying"
        }
    }
}

public struct DynamicBlockRefreshService {
    private let fileManager: FileManager
    private let planner: DynamicBlockPatchPlanner
    private let cacheStore: DynamicBlockCacheStore
    private let writer: AtomicFileWriter

    public init(
        fileManager: FileManager = .default,
        planner: DynamicBlockPatchPlanner = DynamicBlockPatchPlanner(),
        cacheStore: DynamicBlockCacheStore = DynamicBlockCacheStore(),
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        self.fileManager = fileManager
        self.planner = planner
        self.cacheStore = cacheStore
        self.writer = writer
    }

    public func preview(
        markdown: String,
        sourcePath: String,
        root: WorkspaceRoot,
        referenceDate: Date,
        calendar: Calendar = .current
    ) throws -> DynamicBlockRefreshPreview {
        let reader = DailyMarkdownProjectionReader(root: root)
        let tasks = Self.tasksForPreview(
            diskTasks: try reader.allTasks(fileManager: fileManager),
            markdown: markdown,
            sourcePath: sourcePath
        )
        let sources = try reader.allSources(fileManager: fileManager)
        let plan = try planner.plan(
            markdown: markdown,
            sourcePath: sourcePath,
            tasks: tasks,
            sources: sources,
            codexContexts: try reader.allCodexContexts(sources: sources, fileManager: fileManager),
            referenceDate: referenceDate,
            calendar: calendar
        )
        return DynamicBlockRefreshPreview(
            sourcePath: sourcePath,
            sourceContentHash: ContentHasher.hash(markdown),
            plan: plan
        )
    }

    public func apply(
        preview: DynamicBlockRefreshPreview,
        currentMarkdown: String,
        root: WorkspaceRoot
    ) throws -> DynamicBlockRefreshApplyResult {
        guard ContentHasher.hash(currentMarkdown) == preview.sourceContentHash else {
            throw DynamicBlockRefreshError.stalePreview
        }

        let resolved: (url: URL, relativePath: String)
        do {
            resolved = try root.containedFile(preview.sourcePath)
        } catch {
            throw DynamicBlockRefreshError.sourceOutsideWorkspace(preview.sourcePath)
        }

        let updated = try preview.plan.apply(to: currentMarkdown)
        try writer.write(updated, to: resolved.url, fileManager: fileManager)

        var cacheWarning: String?
        do {
            try cacheStore.record(patches: preview.plan.patches, root: root)
        } catch {
            cacheWarning = "dynamic-block cache not recorded (\(error))"
        }
        return DynamicBlockRefreshApplyResult(updatedMarkdown: updated, cacheWarning: cacheWarning)
    }

    private static func tasksForPreview(
        diskTasks: [TaskItem],
        markdown: String,
        sourcePath: String
    ) -> [TaskItem] {
        let currentTasks = TaskParser().parse(
            markdown: DynamicBlockRegion.removingGeneratedRegions(from: markdown),
            notePath: sourcePath
        )
        return (diskTasks.filter { $0.notePath != sourcePath } + currentTasks)
            .sorted { lhs, rhs in
                if lhs.notePath == rhs.notePath {
                    return lhs.lineNumber < rhs.lineNumber
                }
                return lhs.notePath < rhs.notePath
            }
    }
}
