import Foundation

/// Lightweight persistence for app preferences via `UserDefaults`. The workspace root is
/// stored as the raw string the user typed (a leading `~` is preserved) so it round-trips
/// through `WorkspaceRoot.resolve`.
enum SettingsStore {
    private static let workspaceRootKey = "DaymarkWorkspaceRoot"

    static func workspaceRootOverride() -> String? {
        let value = UserDefaults.standard.string(forKey: workspaceRootKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setWorkspaceRootOverride(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: workspaceRootKey)
        } else {
            UserDefaults.standard.removeObject(forKey: workspaceRootKey)
        }
    }
}
