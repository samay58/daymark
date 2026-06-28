import Foundation
import DaymarkCore

/// A read-only snapshot of local workspace health. Computing it never creates or modifies
/// anything, so `daymark doctor` and tests can both rely on it without mutating a workspace.
public struct WorkspaceHealth: Sendable, Equatable {
    public struct DirectoryStatus: Sendable, Equatable {
        public var relativePath: String
        public var exists: Bool

        public init(relativePath: String, exists: Bool) {
            self.relativePath = relativePath
            self.exists = exists
        }
    }

    public var rootRawPath: String
    public var rootExpandedPath: String
    public var directories: [DirectoryStatus]
    public var todayRelativePath: String
    public var todayNoteExists: Bool
    public var dailyMarkdownCount: Int
    public var databasePath: String
    public var databaseExists: Bool
    public var declaredMigrations: [String]

    public var missingDirectoryCount: Int { directories.filter { !$0.exists }.count }
    public var isBootstrapped: Bool { missingDirectoryCount == 0 }

    /// Inspects `root` without creating or modifying anything on disk.
    public static func inspect(
        root: WorkspaceRoot,
        date: Date = Date(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) -> WorkspaceHealth {
        let directories = WorkspaceBootstrapper.requiredRelativeDirectories.map { relative -> DirectoryStatus in
            let url = root.expandedURL.appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            return DirectoryStatus(relativePath: relative, exists: exists)
        }

        let todayRelative = DailyNote.relativePath(for: date, calendar: calendar)
        let todayExists = fileManager.fileExists(atPath: root.expandedURL.appendingPathComponent(todayRelative).path)
        let databaseURL = root.expandedURL.appendingPathComponent(".daymark/daymark.db")

        return WorkspaceHealth(
            rootRawPath: root.rawPath,
            rootExpandedPath: root.expandedPath,
            directories: directories,
            todayRelativePath: todayRelative,
            todayNoteExists: todayExists,
            dailyMarkdownCount: dailyMarkdownCount(root: root, fileManager: fileManager),
            databasePath: databaseURL.path,
            databaseExists: fileManager.fileExists(atPath: databaseURL.path),
            declaredMigrations: MigrationRunner().pendingMigrationNames()
        )
    }

    private static func dailyMarkdownCount(root: WorkspaceRoot, fileManager: FileManager) -> Int {
        let dailyRoot = root.expandedURL.appendingPathComponent("daily", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: dailyRoot, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "md" {
            count += 1
        }
        return count
    }
}
