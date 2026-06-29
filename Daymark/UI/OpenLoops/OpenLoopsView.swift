import SwiftUI
import DaymarkCore

struct OpenLoopsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(DesignTokens.canvas)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textTertiary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(DesignType.body)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
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
