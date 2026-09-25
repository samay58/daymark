import SwiftUI

struct SlipPanelView: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var text = ""
    @State private var saveFailed = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            panel
                .padding(.vertical, 18)
                .padding(.trailing, 18)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text("Capture")
                    .font(DesignType.panelTitle)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Button {
                    handleDiscard()
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignType.controlIcon)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close without saving")
                .accessibilityLabel("Close without saving")
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Capture to Daymark")
                        .font(DesignType.body)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                CaptureTextView(
                    text: $text,
                    onSave: { commit(appState.saveCapture, $0) },
                    onAppendToday: { commit(appState.appendCaptureToToday, $0) },
                    onPromoteTask: { commit(appState.promoteCaptureToTask, $0) },
                    onCancel: { handleDiscard() }
                )
                    .frame(height: 132)
            }
            .fieldChrome()

            HStack(spacing: 8) {
                Button("Append to Today") { commit(appState.appendCaptureToToday, text) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Task") { commit(appState.promoteCaptureToTask, text) }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Text(saveFailed ? "Couldn’t save, text kept" : "⏎ saves")
                    .font(DesignType.metadata)
                    .foregroundStyle(saveFailed ? DesignTokens.warning : DesignTokens.textTertiary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .glassSurface(.floating)
        .onExitCommand { handleDiscard() }
    }

    /// Runs a capture action with the given text and dismisses only on a confirmed save. On
    /// failure the panel stays open with the text intact, so a capture is never lost silently.
    private func commit(_ action: (String) -> Bool, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveFailed = false
        if action(trimmed) {
            text = ""
            isPresented = false
        } else {
            saveFailed = true
        }
    }

    private func handleDiscard() {
        text = ""
        isPresented = false
    }
}
