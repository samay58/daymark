import SwiftUI

// A soft pill used for tags and source references. See mockups 3 (source chips) and the tag row.
struct TagChip: View {
    let label: String
    var tinted: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tinted ? DesignTokens.success : DesignTokens.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tinted ? DesignTokens.accentSoft : DesignTokens.surface)
            .clipShape(Capsule())
    }
}

// Filled sage primary action, e.g. "Create Task File".
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Hairline outline secondary action, e.g. "Edit" / "Preview draft".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.5 : 0.001))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Quiet text action, e.g. "Dismiss" / "Cancel".
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

// Small uppercase letterspaced field label used inside cards.
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.textSecondary)
    }
}
