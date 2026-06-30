import SwiftUI
import DaymarkCore
import DaymarkIndexer

struct DynamicBlockRefreshView: View {
    let preview: DynamicBlockRefreshPreview?
    let message: String?
    let canPreview: Bool
    let canApply: Bool
    let isStale: Bool
    let isPlanning: Bool
    let isApplying: Bool
    var onPreview: () -> Void
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dynamic Blocks")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            content

            if let message {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            actions
        }
        .marginPanel()
    }

    @ViewBuilder
    private var content: some View {
        if isPlanning {
            stateText("Planning refresh.")
        } else if isApplying {
            stateText("Applying refresh.")
        } else if let preview {
            ReadOnlyField(label: "Target", value: preview.plan.targetFilePath, mono: true)
            if isStale {
                stateText("Preview is stale. Preview again before applying.")
            }
            ForEach(Array(preview.plan.patches.enumerated()), id: \.offset) { _, patch in
                patchView(patch)
            }
        } else if canPreview {
            stateText("Dynamic block commands found.")
        } else {
            stateText("No dynamic block commands in this note.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if preview == nil {
            Button("Preview Refresh", action: onPreview)
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(!canPreview || isPlanning || isApplying)
                .opacity((canPreview && !isPlanning && !isApplying) ? 1 : 0.55)
        } else {
            VStack(spacing: 8) {
                Button("Apply Refresh", action: onApply)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(!canApply)
                    .opacity(canApply ? 1 : 0.55)
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func patchView(_ patch: DynamicBlockPatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(patch.rawCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("line \(patch.commandLine), \(operationLabel(patch.operation))")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            markdownPreview(patch.replacementMarkdown)
        }
    }

    private func markdownPreview(_ markdown: String) -> some View {
        ScrollView {
            Text(markdown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DesignTokens.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(maxHeight: 220)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
    }

    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(DesignTokens.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
    }

    private func operationLabel(_ operation: DynamicBlockPatchOperation) -> String {
        switch operation {
        case .insert: return "insert"
        case .replacement: return "replace"
        }
    }
}
