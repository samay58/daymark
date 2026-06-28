import SwiftUI

struct SuggestionCardView: View {
    let prompt: String
    var onPreview: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignTokens.accentSoft)
                    .frame(width: 30, height: 30)
                Image(systemName: "lightbulb")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.accent)
            }

            Text(prompt)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Preview", action: onPreview)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}
