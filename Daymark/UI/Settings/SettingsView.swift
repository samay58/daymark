import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var draftRoot: String = ""
    @State private var isApplying = false

    var body: some View {
        Form {
            Section {
                TextField("Workspace folder", text: $draftRoot, prompt: Text("~/phoenix"))
                    .textFieldStyle(.roundedBorder)
                    .font(DesignType.body)

                HStack(spacing: 10) {
                    Button("Choose…", action: chooseFolder)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Reveal in Finder", action: revealInFinder)
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button(isApplying ? "Applying…" : "Apply", action: apply)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isApplying || normalizedDraft == appState.workspaceRoot.rawPath)
                }
            } header: {
                Text("Workspace")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textSecondary)
            } footer: {
                Text("Markdown notes live here. Changing the folder reloads Today from the new location. Daymark never deletes files outside Daymark.")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { draftRoot = appState.workspaceRoot.rawPath }
    }

    private var normalizedDraft: String {
        let trimmed = draftRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "~/phoenix" : trimmed
    }

    private func apply() {
        isApplying = true
        let target = draftRoot
        Task {
            await appState.changeWorkspaceRoot(target)
            draftRoot = appState.workspaceRoot.rawPath
            isApplying = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            draftRoot = url.path
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appState.workspaceRoot.expandedURL])
    }
}
