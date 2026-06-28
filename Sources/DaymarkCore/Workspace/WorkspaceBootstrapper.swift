import Foundation

public struct WorkspaceBootstrapper {
    public init() {}

    /// The documented Daymark workspace directories, relative to the root.
    /// See the workspace structure in `docs/PRODUCT_SPEC.md`.
    public static let requiredRelativeDirectories: [String] = [
        "daily",
        "slip",
        "inbox",
        "projects",
        "deals",
        "people",
        "meetings",
        "specs/tasks",
        "artifacts/attachments",
        "artifacts/exports",
        "artifacts/context-bundles",
        ".daymark/indexes",
        ".daymark/migrations"
    ]

    public func directories(for root: WorkspaceRoot) -> [URL] {
        Self.requiredRelativeDirectories.map { relative in
            root.expandedURL.appendingPathComponent(relative, isDirectory: true)
        }
    }

    /// Creates any missing documented directories. Idempotent and additive:
    /// existing directories and files are never removed or overwritten.
    @discardableResult
    public func bootstrap(
        root: WorkspaceRoot,
        fileManager: FileManager = .default
    ) throws -> BootstrapReport {
        var created: [String] = []
        for relative in Self.requiredRelativeDirectories {
            let url = root.expandedURL.appendingPathComponent(relative, isDirectory: true)
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists && isDir.boolValue {
                continue
            }
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            created.append(relative)
        }
        return BootstrapReport(root: root, createdDirectories: created)
    }
}

public struct BootstrapReport: Equatable, Sendable {
    public var root: WorkspaceRoot
    public var createdDirectories: [String]

    public init(root: WorkspaceRoot, createdDirectories: [String]) {
        self.root = root
        self.createdDirectories = createdDirectories
    }
}
