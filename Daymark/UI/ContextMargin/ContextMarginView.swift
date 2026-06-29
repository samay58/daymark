import SwiftUI

struct ContextMarginView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SuggestionCardView(
                    prompt: "Create a Codex task from this note?",
                    onPreview: { appState.previewCodexTaskFromSelection() },
                    onDismiss: {}
                )
                CodexTaskComposerView(
                    draft: appState.codexTaskDraft,
                    message: appState.codexTaskMessage,
                    onTitleChange: { appState.updateCodexTaskDraftTitle($0) },
                    onGoalChange: { appState.updateCodexTaskDraftGoal($0) },
                    onConstraintsChange: { appState.updateCodexTaskDraftConstraints($0) },
                    onAcceptanceCriteriaChange: { appState.updateCodexTaskDraftAcceptanceCriteria($0) },
                    onCreate: { appState.createCodexTaskFile() },
                    onCancel: { appState.dismissCodexTaskDraft() }
                )
                if appState.showsContextBundlePanel {
                    CodexContextBundlePreviewView(
                        taskRelativePath: appState.createdCodexTaskRelativePath,
                        bundle: appState.codexContextBundle,
                        message: appState.codexContextBundleMessage,
                        onPreview: { appState.previewCodexContextBundle() },
                        onCreate: { appState.createCodexContextBundle() },
                        onCancel: { appState.dismissCodexContextBundle() }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
        .background(DesignTokens.canvas)
        .overlay(alignment: .leading) {
            Rectangle().fill(DesignTokens.hairline).frame(width: 1)
        }
    }
}
