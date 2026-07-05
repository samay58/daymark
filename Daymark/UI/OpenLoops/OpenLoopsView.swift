import SwiftUI
import DaymarkCore

struct OpenLoopsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .glassSurface()
        .task { await appState.refreshOpenLoops() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DesignTokens.accent)
            Text("Open Loops")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("\(appState.openLoopCount)")
                .font(DesignType.metadata)
                .foregroundStyle(DesignTokens.textTertiary)
            Spacer()
            Button {
                Task { await appState.refreshOpenLoops() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
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
            Text(appState.isRefreshingOpenLoops ? "Refreshing" : "No open loops")
                .font(DesignType.sectionHeading)
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
                    .font(DesignType.sectionHeading)
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
            .background(Color.white.opacity(0.48))
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

    private var isDone: Bool { task.status == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OpenLoopCheckbox(done: isDone)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(DesignType.body)
                    .foregroundStyle(isDone ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                    .strikethrough(isDone)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.tags.isEmpty || task.due != nil {
                    HStack(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            TokenPill(text: tag, fill: DesignTokens.accentSoft, textColor: DesignTokens.accentDeep)
                        }
                        if let due = task.due {
                            TokenPill(
                                text: Self.dueDisplay(due),
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

    // Mirrors NoteTokenScanner's private due-token humanizer (Today / Tomorrow / "Jul 8"),
    // which is not exposed publicly; kept here as the same MMM-d, en_US_POSIX, Gregorian recipe.
    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static func dueDisplay(_ due: TaskItem.Due) -> String {
        switch due {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .date(let iso):
            guard let date = ISODate.date(from: iso) else { return iso }
            return dueFormatter.string(from: date)
        }
    }
}

// Matches the live editor's task checkbox geometry and colors (16x16, radius 4,
// checkboxBorder stroke, accent fill with a white check when done). Display-only: Open
// Loops row actions are frozen, so this never handles a tap.
private struct OpenLoopCheckbox: View {
    let done: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: DesignMetrics.checkboxRadius, style: .continuous)
            .fill(done ? DesignTokens.accent : Color.clear)
            .overlay {
                if !done {
                    RoundedRectangle(cornerRadius: DesignMetrics.checkboxRadius, style: .continuous)
                        .stroke(DesignTokens.checkboxBorder, lineWidth: 1)
                }
            }
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: DesignMetrics.checkboxSize, height: DesignMetrics.checkboxSize)
    }
}
