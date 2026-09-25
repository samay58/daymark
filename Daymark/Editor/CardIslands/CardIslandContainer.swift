import SwiftUI
import DaymarkCore

struct CardIslandContext {
    let region: NoteTokens.GeneratedRegion
    let command: DynamicBlockCommand?
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
    /// The command named on a `/daymark <command> [args]` line.
    static func parse(_ line: String?) -> DynamicBlockCommand? {
        line.flatMap(DynamicBlockParser.knownCommand(onLine:))
    }

    /// "Generated" covers a region with no adjacent command line, or one naming an unknown command.
    static func title(for command: DynamicBlockCommand?) -> String {
        command?.blockTitle ?? "Generated"
    }
}
