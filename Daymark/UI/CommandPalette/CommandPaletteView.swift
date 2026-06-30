import AppKit
import SwiftUI
import DaymarkStore

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var availableCommands: [PaletteCommand] {
        SampleData.paletteCommands.filter { command in
            command.action != .refreshDynamicBlocks || appState.canRefreshDynamicBlocks
        }
    }

    private var commandResults: [PaletteCommand] {
        guard !query.isEmpty else { return availableCommands }
        return availableCommands.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
            resultsList
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
        .onAppear { isFocused = true }
        .onDisappear { appState.clearSearch() }
        .onExitCommand { isPresented = false }
        .onMoveCommand { direction in move(direction) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.textSecondary)
            TextField("Search notes and commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.textPrimary)
                .focused($isFocused)
                .onSubmit { executeSelectedCommand() }
                .onChange(of: query) { _, newValue in
                    selectedIndex = 0
                    if trimmedQuery.isEmpty {
                        appState.clearSearch()
                    } else {
                        appState.runSearch(newValue)
                    }
                }
            Text("⌘K")
                .font(DesignType.metadata)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !trimmedQuery.isEmpty {
                    notesSection
                }
                commandsSection
                if commandResults.isEmpty && appState.searchResults.isEmpty {
                    Text("Nothing matches \"\(query)\"")
                        .font(DesignType.palette)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(16)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 360)
    }

    @ViewBuilder
    private var notesSection: some View {
        if !appState.searchResults.isEmpty {
            sectionHeader("NOTES")
            ForEach(appState.searchResults, id: \.relativePath) { hit in
                NoteResultRow(hit: hit)
                    .onTapGesture { isPresented = false }
            }
        }
    }

    @ViewBuilder
    private var commandsSection: some View {
        if !commandResults.isEmpty {
            sectionHeader("ACTIONS")
            ForEach(Array(commandResults.enumerated()), id: \.element.id) { index, command in
                CommandRow(command: command, isSelected: index == selectedIndex)
                    .onTapGesture { execute(command) }
                    .onHover { hovering in
                        if hovering { selectedIndex = index }
                    }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(DesignTokens.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func move(_ direction: MoveCommandDirection) {
        guard !commandResults.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(commandResults.count - 1, selectedIndex + 1)
        default:
            break
        }
    }

    private func executeSelectedCommand() {
        guard !commandResults.isEmpty, selectedIndex < commandResults.count else {
            isPresented = false
            return
        }
        execute(commandResults[selectedIndex])
    }

    private func execute(_ command: PaletteCommand) {
        switch command.action {
        case .openToday:
            appState.selectedSidebarItem = .today
        case .showOpenLoops:
            appState.selectedSidebarItem = .openLoops
        case .createCodexTask:
            appState.previewCodexTaskFromSelection()
        case .refreshDynamicBlocks:
            Task { await appState.previewDynamicBlocksRefresh() }
        case .openWorkspaceInFinder:
            NSWorkspace.shared.open(appState.workspaceRoot.expandedURL)
        case .searchNotes, .appendSelectionToToday, .runDoctor:
            break
        }
        isPresented = false
    }
}

private struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 14))
                .frame(width: 18)
                .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.textSecondary)
            Text(command.title)
                .font(DesignType.palette)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer(minLength: 8)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? DesignTokens.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

private struct NoteResultRow: View {
    let hit: SearchHit
    @State private var isHovering = false

    private var displayTitle: String {
        if let title = hit.title, !title.isEmpty { return title }
        return (hit.relativePath as NSString).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .frame(width: 18)
                .foregroundStyle(isHovering ? DesignTokens.accent : DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(DesignType.palette)
                    .foregroundStyle(DesignTokens.textPrimary)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(DesignType.metadata)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHovering ? DesignTokens.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
