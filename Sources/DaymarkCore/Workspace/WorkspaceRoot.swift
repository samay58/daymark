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
