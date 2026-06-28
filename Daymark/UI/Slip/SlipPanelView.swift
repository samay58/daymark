import SwiftUI

struct SlipPanelView: View {
    @Binding var isPresented: Bool
    @State private var text = ""
    @FocusState private var isFocused: Bool

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Quickly save what matters.")
                        .font(DesignType.metadata)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Button {
                    isPresented = false
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
                TextEditor(text: $text)
                    .font(DesignType.body)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(height: 132)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
            }
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Button("Append to Today") {}
                    .buttonStyle(SecondaryButtonStyle())
                Button("Task") {}
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
        .onAppear { isFocused = true }
        .onExitCommand { isPresented = false }
    }
}
