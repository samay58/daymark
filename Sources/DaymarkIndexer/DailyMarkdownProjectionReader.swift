import Foundation
import DaymarkCore

/// The single Markdown-to-projection reader for daily notes. It owns daily-file
/// enumeration, workspace-relative path computation, and per-file projection (read,
/// strip generated dynamic-block regions, parse blocks and tasks). Both the SQLite
/// indexer and the CLI route through it so daily scanning never drifts between the two.
/// Markdown remains the source of truth; this reader does not touch SQLite.
public struct DailyMarkdownProjectionReader {
    public let root: WorkspaceRoot
    private let parser = MarkdownParser()
    private let taskParser = TaskParser()

    public init(root: WorkspaceRoot) {
        self.root = root
    }

    /// A daily note projected from its Markdown. `tasks` already has generated dynamic-block
    /// regions stripped, so rendered checklist lines never feed back into the task index.
    public struct Projection: Sendable {
        public var relativePath: String
        public var content: String
        public var title: String?
        public var blocks: [Block]
        public var tasks: [TaskItem]
        public var modifiedAt: Date?
    }

    /// Workspace-relative paths of every daily Markdown file, sorted by path.
    public func dailyRelativePaths(fileManager: FileManager = .default) -> [String] {
        let dailyRoot = root.expandedURL.appendingPathComponent("daily", isDirectory: true)
        return Self.markdownFiles(under: dailyRoot, fileManager: fileManager)
            .map { Self.relativePath(of: $0, under: root) }
    }

    /// Projects a single workspace-relative Markdown file, or nil if it does not exist.
    public func projection(relativePath: String, fileManager: FileManager = .default) throws -> Projection? {
        let url = root.expandedURL.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let content = try String(contentsOf: url, encoding: .utf8)
        let modifiedAt = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return Projection(
            relativePath: relativePath,
            content: content,
            title: parser.title(from: content),
            blocks: parser.blocks(from: content),
            tasks: taskParser.parse(
                markdown: DynamicBlockRegion.removingGeneratedRegions(from: content),
                notePath: relativePath
            ),
            modifiedAt: modifiedAt
        )
    }

    /// Tasks parsed from every daily Markdown file (generated regions stripped) in path then
    /// line order. This is the Markdown-derived equivalent of `Database.openTasks()` input,
    /// used by read-only CLI paths that must reflect the files on disk rather than the index.
    public func allTasks(fileManager: FileManager = .default) throws -> [TaskItem] {
        var tasks: [TaskItem] = []
        for relativePath in dailyRelativePaths(fileManager: fileManager) {
            if let projection = try projection(relativePath: relativePath, fileManager: fileManager) {
                tasks.append(contentsOf: projection.tasks)
            }
        }
        return tasks
    }

    /// Tagged Markdown sources across the workspace, sorted by path. Generated dynamic-block
    /// regions and visible `/daymark ...` command lines are ignored for tag matching, so a
    /// `source-list` command does not make its own note match.
    public func allSources(fileManager: FileManager = .default) throws -> [DynamicBlockSource] {
        var sources: [DynamicBlockSource] = []
        for relativePath in workspaceMarkdownRelativePaths(fileManager: fileManager) {
            let url = root.expandedURL.appendingPathComponent(relativePath)
            let content = try String(contentsOf: url, encoding: .utf8)
            let tags = Self.sourceTags(in: content)
            guard !tags.isEmpty else { continue }
            sources.append(DynamicBlockSource(
                title: parser.title(from: content) ?? relativePath,
                relativePath: relativePath,
                tags: tags
            ))
        }
        return sources
    }

    // MARK: - Helpers (single home for daily enumeration + relative-path computation)

    private func workspaceMarkdownRelativePaths(fileManager: FileManager) -> [String] {
        Self.markdownFiles(under: root.expandedURL, fileManager: fileManager)
            .map { Self.relativePath(of: $0, under: root) }
            .filter { !$0.hasPrefix(".daymark/") }
    }

    static func markdownFiles(under directory: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    static func relativePath(of url: URL, under root: WorkspaceRoot) -> String {
        // Resolve symlinks on both sides so temp roots like /var -> /private/var, which the
        // directory enumerator canonicalizes, still strip cleanly.
        let rootPath = root.expandedURL.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func sourceTags(in markdown: String) -> [String] {
        let stripped = DynamicBlockRegion.removingGeneratedRegions(from: markdown)
        let lines = stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var fence = MarkdownFenceScanner()
        var tags: Set<String> = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence.consume(trimmedLine: trimmed) { continue }
            if fence.isInsideFence { continue }
            if trimmed.hasPrefix("/daymark ") || trimmed == "/daymark" { continue }

            for word in trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                guard word.hasPrefix("#"), word.count > 1 else { continue }
                tags.insert(String(word))
            }
        }

        return tags.sorted()
    }
}
