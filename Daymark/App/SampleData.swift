import Foundation

// Fake data for the Milestone 0 taste prototype. No real workspace is read or written.
enum SampleData {
    static let todayDocument = """
    ## Brief

    Ship the new onboarding flow.
    Review the data model for links.
    Write notes on the screen side.
    Short run in the evening.

    ## Tasks

    - [x] Draft onboarding copy
    - [x] Sync with design on illustrations
    - [ ] Implement local search
    - [ ] Add link previews

    ## Notes

    Exploring lightweight link previews that don't break flow. See [[link previews]] for ideas.

    > Clarity is not just about what you remove, but what you make obvious.
    > John Maeda

    #product #daily
    """

    static let paletteCommands: [PaletteCommand] = [
        PaletteCommand(action: .openToday, title: "Open Today", symbol: "sun.max", shortcut: "⌘1"),
        PaletteCommand(action: .searchNotes, title: "Search Notes", symbol: "magnifyingglass", shortcut: nil),
        PaletteCommand(action: .showOpenLoops, title: "Open Loops", symbol: "circle.dashed", shortcut: "⌘L"),
        PaletteCommand(
            action: .createCodexTask,
            title: "Create Codex Task from Selection",
            symbol: "doc.badge.plus",
            shortcut: "⇧⌘C"
        ),
        PaletteCommand(
            action: .refreshDynamicBlocks,
            title: "Refresh Dynamic Blocks",
            symbol: "arrow.triangle.2.circlepath",
            shortcut: "⇧⌘R"
        ),
        PaletteCommand(action: .appendSelectionToToday, title: "Append Selection to Today", symbol: "text.append", shortcut: nil),
        PaletteCommand(action: .openWorkspaceInFinder, title: "Open Workspace in Finder", symbol: "folder", shortcut: nil),
        PaletteCommand(action: .runDoctor, title: "Run Doctor", symbol: "stethoscope", shortcut: nil)
    ]
}

enum PaletteCommandAction: String {
    case openToday
    case searchNotes
    case showOpenLoops
    case createCodexTask
    case refreshDynamicBlocks
    case appendSelectionToToday
    case openWorkspaceInFinder
    case runDoctor
}

struct PaletteCommand: Identifiable {
    var id: String { action.rawValue }
    let action: PaletteCommandAction
    let title: String
    let symbol: String
    let shortcut: String?
}
