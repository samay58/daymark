import SwiftUI
import DaymarkCore

struct OpenLoopsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .glassSurface(.overlay)
        .task { await appState.refreshOpenLoops() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dashed")
                .font(DesignType.panelIcon)
                .foregroundStyle(DesignTokens.accent)
            Text("Open Loops")
                .font(DesignType.panelTitle)
                .foregroundStyle(DesignTokens.textPrimary)
            Text("\(appState.openLoopCount)")
                .font(DesignType.metadata)
                .foregroundStyle(DesignTokens.textTertiary)
            Spacer()
            Button {
                Task { await appState.refreshOpenLoops() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignType.controlIcon)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh open loops")
            .accessibilityLabel("Refresh open loops")
            // Escape reaches this through the window's key equivalents, so it closes the
            // overlay even while the editor behind it keeps keyboard focus.
            Button {
                appState.isOpenLoopsOverlayPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(DesignType.controlIcon)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close open loops")
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.openLoopGroups.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(appState.openLoopGroups, id: \.bucket) { group in
                        OpenLoopSectionView(group: group)
                    }
                }
                .frame(maxWidth: DesignMetrics.editorMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 40)
                .padding(.top, 34)
                .padding(.bottom, 40)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.isRefreshingOpenLoops ? "Refreshing…" : "No open loops")
                .font(DesignType.heading(level: 2))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Captured tasks will appear here after the local index refreshes.")
                .font(DesignType.body)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: DesignMetrics.editorMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 40)
        .padding(.top, 54)
    }
}

private struct OpenLoopSectionView: View {
    let group: OpenLoopGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.bucket.title)
                    .font(DesignType.heading(level: 2))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("\(group.tasks.count)")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.tasks.enumerated()), id: \.offset) { index, task in
                    OpenLoopTaskRow(task: task)
                    if index < group.tasks.count - 1 {
                        Rectangle().fill(DesignTokens.hairline).frame(height: 1)
                    }
                }
            }
            .background(DesignTokens.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
        }
    }
}

private struct OpenLoopTaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OpenLoopCheckbox()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(DesignType.body)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.tags.isEmpty || task.due != nil {
                    HStack(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            TokenPill(text: tag, fill: DesignTokens.accentSoft, textColor: DesignTokens.accentDeep)
                        }
                        if let due = task.due {
                            TokenPill(
                                text: due.displayText(),
                                fill: DesignTokens.pillDueFill,
                                textColor: DesignTokens.textSecondary,
                                leadingSymbol: "clock"
                            )
                        }
                    }
                }

                Text("\(task.notePath):\(task.lineNumber)")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

// The editor's empty checkbox, drawn from the same metrics. Open Loops lists only open tasks,
// and a row is not a toggle, so there is no done state and no tap.
private struct OpenLoopCheckbox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignMetrics.checkboxRadius, style: .continuous)
            .stroke(DesignTokens.checkboxBorder, lineWidth: DesignMetrics.checkboxStroke)
            .frame(width: DesignMetrics.checkboxSize, height: DesignMetrics.checkboxSize)
            .accessibilityHidden(true)
    }
}
