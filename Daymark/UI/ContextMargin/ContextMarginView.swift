import SwiftUI

struct ContextMarginView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SuggestionCardView(
                    prompt: "Draft follow-up from meeting notes?",
                    onPreview: { appState.isContextMarginVisible = true },
                    onDismiss: {}
                )
                CodexTaskComposerView()
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
