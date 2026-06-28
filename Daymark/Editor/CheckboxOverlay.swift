import SwiftUI

struct CheckboxOverlay: View {
    let isCompleted: Bool

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
            .foregroundStyle(isCompleted ? DesignTokens.accent : DesignTokens.textSecondary)
    }
}
