import SwiftUI
import DaymarkCore

struct CodexTaskComposerView: View {
    let draft: CodexTaskDraft?
    let message: String?
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Codex Task")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            if let draft {
                preview(for: draft)
            } else {
                emptyState
            }

            if let message {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            VStack(spacing: 8) {
                Button("Create Task File", action: onCreate)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(draft == nil)
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private func preview(for draft: CodexTaskDraft) -> some View {
        field("Title", value: draft.title)
        field("Goal", value: draft.goal, lines: 2)
        field("Source", value: sourceLabel(for: draft), mono: true)
        field("Excerpt", value: draft.sourceExcerpt, lines: 4, mono: true)

        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Acceptance Criteria")
            VStack(alignment: .leading, spacing: 7) {
                ForEach(displayCriteria(for: draft), id: \.self) { item in
                    criterion(item)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
        }

        field("File", value: draft.suggestedFilePath, mono: true)
        field("Markdown", value: draft.markdown(), lines: 8, mono: true)
    }

    private var emptyState: some View {
        Text("No task preview yet.")
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

    private func field(_ label: String, value: String, lines: Int = 1, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 17, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                }
        }
    }

    private func criterion(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func sourceLabel(for draft: CodexTaskDraft) -> String {
        if let line = draft.sourceLine {
            if let endLine = draft.sourceEndLine, endLine > line {
                return "\(draft.sourcePath):\(line)-\(endLine)"
            }
            return "\(draft.sourcePath):\(line)"
        }
        return draft.sourcePath
    }

    private func displayCriteria(for draft: CodexTaskDraft) -> [String] {
        let markdown = draft.markdown()
        return markdown.components(separatedBy: "\n")
            .filter { $0.hasPrefix("- [ ] ") }
            .map { String($0.dropFirst(6)) }
    }
}
