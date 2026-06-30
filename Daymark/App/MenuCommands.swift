import SwiftUI

struct MenuCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandMenu("Daymark") {
            Button("Open Today") {
                appState.selectedSidebarItem = .today
                appState.isCommandPalettePresented = false
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Capture to Slip") {
                appState.isSlipPresented.toggle()
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Button("Command Palette") {
                appState.isCommandPalettePresented.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Create Codex Task from Selection") {
                appState.previewCodexTaskFromSelection()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Refresh Dynamic Blocks") {
                Task { await appState.previewDynamicBlocksRefresh() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appState.canRefreshDynamicBlocks)

            Divider()

            Button(appState.isContextMarginVisible ? "Hide Context Margin" : "Show Context Margin") {
                appState.isContextMarginVisible.toggle()
            }
            .keyboardShortcut("\\", modifiers: [.command, .option])
        }
    }
}
