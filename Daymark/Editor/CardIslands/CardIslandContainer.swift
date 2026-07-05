import SwiftUI
import DaymarkCore

struct CardIslandContext {
    let region: NoteTokens.GeneratedRegion
    let command: String?
    let innerText: String
    /// Composite reveal state (caret intersecting the region, or the view-source toggle
    /// switched on). Drives which chrome a provider shows; the caller does not need to track
    /// caret vs. user reveal separately.
    let isRevealed: Bool
    /// Sets the user-driven half of reveal state. Toggling to `false` clears only the user
    /// reveal; the region stays revealed if the caret is still inside it.
    let setSourceRevealed: (Bool) -> Void
    let notifyHeightChanged: () -> Void
}

typealias CardIslandContentProvider = (CardIslandContext) -> AnyView

enum CardIslandCommand {
    static func parse(_ line: String?) -> String? {
        guard let line else { return nil }
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.first == "/daymark", parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    static func title(for command: String?) -> String {
        switch command {
        case "open-loops": return "OPEN LOOPS"
        case "source-list": return "SOURCES"
        case "codex-context": return "CODEX CONTEXT"
        case "weekly-review": return "WEEKLY REVIEW"
        default: return "GENERATED"
        }
    }
}

enum CardIslandProviders {
    static let placeholder: CardIslandContentProvider = { context in
        AnyView(
            CardIslandPlaceholderView(
                title: CardIslandCommand.title(for: context.command),
                innerText: context.innerText,
                notifyHeightChanged: context.notifyHeightChanged
            )
        )
    }
}

struct CardIslandPlaceholderView: View {
    let title: String
    let innerText: String
    var notifyHeightChanged: () -> Void
    @State private var showingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title)
                    .font(DesignType.cardHeader)
                    .tracking(0.5)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer(minLength: 8)
                Button {
                    showingSource.toggle()
                    notifyHeightChanged()
                } label: {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showingSource ? DesignTokens.accentDeep : DesignTokens.textTertiary)
                }
                .buttonStyle(.plain)
                .help("View source")
            }
            if showingSource {
                Text(innerText.isEmpty ? "(empty region)" : innerText)
                    .font(DesignType.code)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Card placeholder. Content view arrives next.")
                    .font(DesignType.body)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.cardIslandFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
    }
}
