import SwiftUI

struct TodayView: View {
    @Binding var text: String
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if appState.hasExternalConflict {
                conflictBanner
            }
            documentBody
        }
        .background(DesignTokens.canvas)
    }

    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            @Bindable var appState = appState
            DaymarkEditorView(
                text: $text,
                selection: $appState.editorSelection,
                sourcePath: appState.todayRelativePath
            )
                .padding(.top, 14)
        }
        .frame(maxWidth: DesignMetrics.editorMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 40)
        .padding(.top, DesignMetrics.editorTopPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                DateTile(day: Self.dayNumber(from: Date()))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.monthFormatter.string(from: Date()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(Self.weekdayFormatter.string(from: Date()))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    ToolbarIcon(symbol: "square.and.pencil") { appState.isSlipPresented = true }
                    ToolbarIcon(symbol: "magnifyingglass") { appState.showCommandPalette(prefill: nil) }
                    ToolbarIcon(symbol: "circle.dashed") { appState.toggleOpenLoopsOverlay() }
                }
            }

            briefStrip

            Rectangle()
                .fill(DesignTokens.hairline)
                .frame(height: 1)
                .padding(.top, 8)
        }
    }

    private var briefStrip: some View {
        BriefStripText(segments: briefStripSegments)
            .contentShape(Rectangle())
            .onTapGesture { appState.toggleOpenLoopsOverlay() }
    }

    private var briefStripSegments: [String] {
        var segments: [String] = []
        if appState.rolledOverCount > 0 {
            segments.append("\(appState.rolledOverCount) rolled over")
        }
        if appState.openLoopCount > 0 {
            segments.append("\(appState.openLoopCount) open loops")
        }
        segments.append(appState.isSaving ? "Saving" : "Saved")
        return segments
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .padding(.horizontal, 40)
        .padding(.top, 16)
    }

    private static func dayNumber(from date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

private struct BriefStripText: View {
    let segments: [String]
    @State private var isHovering = false

    var body: some View {
        Text(segments.joined(separator: " · "))
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovering ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .onHover { hovering in
                withAnimation(DesignMotion.hover) { isHovering = hovering }
            }
    }
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
