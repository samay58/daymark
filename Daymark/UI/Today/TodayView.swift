import SwiftUI

struct TodayView: View {
    @Binding var text: String
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if appState.hasExternalConflict {
                conflictBanner
            }
            documentBody
            statusBar
        }
        .background(DesignTokens.canvas)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ToolbarIcon(symbol: "chevron.left")
                ToolbarIcon(symbol: "chevron.right")
            }
            HStack(spacing: 5) {
                Text(appState.workspaceRoot.rawPath)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.textSecondary)

            Spacer()

            ToolbarIcon(symbol: "square.and.pencil") { appState.isSlipPresented = true }
            ToolbarIcon(symbol: "magnifyingglass") { appState.isCommandPalettePresented = true }
            ToolbarIcon(symbol: "sidebar.right") { appState.isContextMarginVisible.toggle() }
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .padding(.top, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
        }
    }

    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DaymarkEditorView(text: $text)
                .padding(.top, 14)
        }
        .frame(maxWidth: DesignMetrics.editorMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 40)
        .padding(.top, DesignMetrics.editorTopPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dateTitleFormatter.string(from: Date()))
                .font(DesignType.dailyDate)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(Self.dateSubtitleFormatter.string(from: Date()))
                .font(DesignType.dailySubtitle)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 6)

            Rectangle()
                .fill(DesignTokens.hairline)
                .frame(height: 1)
                .padding(.top, 22)
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.warning)
            Text("This note changed on disk while you had unsaved edits.")
                .font(DesignType.metadata)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Button("Keep mine") { appState.keepLocalVersion() }
                .buttonStyle(QuietButtonStyle())
            Button("Use disk version") { appState.acceptExternalChange() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(DesignTokens.surfaceWarm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
        }
    }

    private var statusBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text("\(wordCount) words")
                Image(systemName: "chart.bar")
                    .font(.system(size: 11))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                Text("Saved to \(appState.workspaceRoot.rawPath)")
            }
        }
        .font(DesignType.metadata)
        .foregroundStyle(DesignTokens.textTertiary)
        .padding(.horizontal, 24)
        .frame(height: 40)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
        }
    }

    private var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }

    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateSubtitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
}

private struct ToolbarIcon: View {
    let symbol: String
    var action: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isHovering ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .frame(width: 26, height: 26)
                .background(isHovering ? Color.black.opacity(0.04) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignMotion.hover) { isHovering = hovering }
        }
    }
}
