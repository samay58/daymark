import Foundation
import DaymarkCore
import DaymarkStore

/// Projects Markdown daily notes into the SQLite index. The projection is a pure
/// function of the files on disk: indexing is idempotent and the database can be
/// rebuilt from the Markdown at any time. Markdown remains the source of truth.
public struct WorkspaceIndexer {
    public let root: WorkspaceRoot
    public let database: Database
    public let calendar: Calendar
    private let parser = MarkdownParser()

    public init(root: WorkspaceRoot, database: Database, calendar: Calendar = .current) {
        self.root = root
        self.database = database
        self.calendar = calendar
    }

    /// Reads a workspace-relative Markdown file, parses it into blocks, and upserts the
    /// projection. Returns false when the file does not exist. Never appends on reindex.
    @discardableResult
    public func indexFile(relativePath: String, fileManager: FileManager = .default) async throws -> Bool {
        let url = root.expandedURL.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let content = try String(contentsOf: url, encoding: .utf8)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes?[.modificationDate] as? Date

        let repository = NoteRepository(database: database)
        try await repository.projectNote(
            relativePath: relativePath,
            title: parser.title(from: content),
            content: content,
            modifiedAt: modifiedAt,
            blocks: parser.blocks(from: content)
        )
        return true
    }

    /// Indexes today's daily note.
    public func indexToday(date: Date = Date(), fileManager: FileManager = .default) async throws {
        let relativePath = DailyNote.relativePath(for: date, calendar: calendar)
        _ = try await indexFile(relativePath: relativePath, fileManager: fileManager)
    }

    /// Reprojects every daily Markdown file under `daily/`. Returns the number of files
    /// indexed. Safe to run against a fresh database to reconstruct the full projection.
    @discardableResult
    public func rebuild(fileManager: FileManager = .default) async throws -> Int {
        let dailyRoot = root.expandedURL.appendingPathComponent("daily", isDirectory: true)
        var indexed = 0
        for url in Self.markdownFiles(under: dailyRoot, fileManager: fileManager) {
            let relativePath = Self.relativePath(of: url, under: root)
            if try await indexFile(relativePath: relativePath, fileManager: fileManager) {
                indexed += 1
            }
        }
        return indexed
    }

    // MARK: - Helpers

    private static func markdownFiles(under directory: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func relativePath(of url: URL, under root: WorkspaceRoot) -> String {
        // Resolve symlinks on both sides so temp roots like /var -> /private/var,
        // which the directory enumerator canonicalizes, still strip cleanly.
        let rootPath = root.expandedURL.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
