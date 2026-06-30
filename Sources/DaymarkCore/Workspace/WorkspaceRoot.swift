import Foundation

public struct WorkspaceRoot: Equatable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    /// The default workspace is the `~/phoenix` vault: Daymark operates directly on the
    /// existing Markdown knowledge base. Bootstrap is additive, so it only adds the Daymark
    /// directories it does not already find. See ADR-005 (reversed).
    public static let defaultWorkspace = WorkspaceRoot(path: "~/phoenix")

    /// The configured path as written, which may contain a leading `~`.
    public var rawPath: String { path }

    /// The path with `~` expanded to the user's home directory.
    public var expandedPath: String {
        (path as NSString).expandingTildeInPath
    }

    public var expandedURL: URL {
        URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    /// Relative paths of the Markdown files directly inside `subdirectory` (for example
    /// "specs/tasks" or "artifacts/context-bundles"), used to pick collision-safe file names
    /// before writing. Returns an empty set when the directory does not exist yet.
    public func existingMarkdownRelativePaths(
        under subdirectory: String,
        fileManager: FileManager = .default
    ) -> Set<String> {
        let directory = expandedURL.appendingPathComponent(subdirectory, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(files.filter { $0.pathExtension == "md" }.map { "\(subdirectory)/\($0.lastPathComponent)" })
    }

    /// Resolves a user-supplied source path that must live inside the workspace, returning
    /// the resolved file URL and its canonical workspace-relative path. Absolute paths and
    /// `..` escapes that canonicalize outside the workspace root are rejected, so a command
    /// that writes back into its source (for example `daymark blocks refresh --apply`) can
    /// never mutate a file outside `~/phoenix`. The file is not required to exist; this is a
    /// pure containment check that callers run before their own existence check.
    public func containedFile(_ path: String) throws -> (url: URL, relativePath: String) {
        let rootURL = expandedURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let expandedInput = (path as NSString).expandingTildeInPath
        let candidate = expandedInput.hasPrefix("/")
            ? URL(fileURLWithPath: expandedInput)
            : rootURL.appendingPathComponent(expandedInput)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedPath = resolved.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw WorkspacePathError.outsideWorkspace(path)
        }
        let relativePath = resolvedPath == rootPath ? "" : String(resolvedPath.dropFirst(rootPath.count + 1))
        return (resolved, relativePath)
    }

    public static let environmentOverrideKey = "DAYMARK_WORKSPACE_ROOT"

    /// Resolves the workspace root with precedence: explicit override, then the
    /// `DAYMARK_WORKSPACE_ROOT` environment variable, then the `~/phoenix` default.
    public static func resolve(
        override explicit: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WorkspaceRoot {
        if let explicit, !explicit.isEmpty {
            return WorkspaceRoot(path: explicit)
        }
        if let env = environment[environmentOverrideKey], !env.isEmpty {
            return WorkspaceRoot(path: env)
        }
        return .defaultWorkspace
    }
}

public enum WorkspacePathError: LocalizedError, Equatable {
    case outsideWorkspace(String)

    public var errorDescription: String? {
        switch self {
        case .outsideWorkspace(let path):
            return "source path is outside the workspace: \(path)"
        }
    }
}
