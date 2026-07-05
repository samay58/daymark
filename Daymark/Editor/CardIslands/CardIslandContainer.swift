import SwiftUI
import DaymarkCore

struct CardIslandContext {
    let region: NoteTokens.GeneratedRegion
    let command: String?
    let innerText: String
    /// Composite reveal state (caret intersecting the region, or the view-source toggle
    /// switched on). Drives which chrome a provider shows; the caller does not need to track
    /// caret vs. user reveal separately.
    let isRevealed: Bool
    /// Sets the user-driven half of reveal state. Toggling to `false` clears only the user
    /// reveal; the region stays revealed if the caret is still inside it.
    let setSourceRevealed: (Bool) -> Void
    let notifyHeightChanged: () -> Void
}

typealias CardIslandContentProvider = (CardIslandContext) -> AnyView

enum CardIslandCommand {
    static func parse(_ line: String?) -> String? {
        guard let line else { return nil }
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.first == "/daymark", parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    static func title(for command: String?) -> String {
        switch command {
        case "open-loops": return "Open Loops"
        case "source-list": return "Sources"
        case "codex-context": return "Codex Context"
        case "weekly-review": return "Weekly Review"
        default: return "Generated"
        }
    }
}
