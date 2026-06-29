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

    struct SidebarRow: Identifiable {
        var id: SidebarItem { item }
        let item: SidebarItem
        let symbol: String
        let title: String
        var count: Int?
    }

    static let primaryRows: [SidebarRow] = [
        SidebarRow(item: .today, symbol: "sun.max", title: "Today"),
        SidebarRow(item: .notes, symbol: "doc.text", title: "Notes"),
        SidebarRow(item: .scratchpad, symbol: "pencil", title: "Scratchpad"),
        SidebarRow(item: .openLoops, symbol: "circle.dashed", title: "Open Loops", count: 7),
        SidebarRow(item: .calendar, symbol: "calendar", title: "Calendar")
    ]

    static let secondaryRows: [SidebarRow] = [
        SidebarRow(item: .archive, symbol: "archivebox", title: "Archive"),
        SidebarRow(item: .tags, symbol: "tag", title: "Tags"),
        SidebarRow(item: .settings, symbol: "gearshape", title: "Settings")
    ]

    static let paletteCommands: [PaletteCommand] = [
        PaletteCommand(title: "Open Today", symbol: "sun.max", shortcut: "⌘1"),
        PaletteCommand(title: "Search Notes", symbol: "magnifyingglass", shortcut: nil),
        PaletteCommand(title: "Show Open Loops", symbol: "circle.dashed", shortcut: nil),
        PaletteCommand(title: "Create Codex Task from Selection", symbol: "doc.badge.plus", shortcut: "⇧⌘C"),
        PaletteCommand(title: "Append Selection to Today", symbol: "text.append", shortcut: nil),
        PaletteCommand(title: "Open Workspace in Finder", symbol: "folder", shortcut: nil),
        PaletteCommand(title: "Run Doctor", symbol: "stethoscope", shortcut: nil)
    ]
}

enum SidebarItem: Hashable {
    case today, notes, scratchpad, openLoops, calendar, archive, tags, settings
}

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let shortcut: String?
}
