import SwiftUI

struct SlipPanelView: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var text = ""

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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Button {
                    handleDiscard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
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
                    onSave: { _ in withTrimmedText(appState.saveCapture) },
                    onAppendToday: { _ in withTrimmedText(appState.appendCaptureToToday) },
                    onPromoteTask: { _ in withTrimmedText(appState.promoteCaptureToTask) },
                    onCancel: { handleDiscard() }
                )
                    .frame(height: 132)
            }
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Button("Append to Today") { handleAppendToday() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Task") { handlePromoteTask() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Text("⏎ saves")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .onExitCommand { handleDiscard() }
    }

    private func withTrimmedText(_ handler: (String) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        handler(trimmed)
        text = ""
        isPresented = false
    }

    private func handleAppendToday() {
        withTrimmedText(appState.appendCaptureToToday)
    }

    private func handlePromoteTask() {
        withTrimmedText(appState.promoteCaptureToTask)
    }

    private func handleDiscard() {
        text = ""
        isPresented = false
    }
}
