import SwiftUI
import DaymarkCore

struct CodexTaskComposerView: View {
    let draft: CodexTaskDraft?
    let message: String?
    var onTitleChange: (String) -> Void
    var onGoalChange: (String) -> Void
    var onConstraintsChange: (String) -> Void
    var onAcceptanceCriteriaChange: (String) -> Void
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Codex Task")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            if let draft {
                EditableCodexTaskDraftView(
                    draft: draft,
                    onTitleChange: onTitleChange,
                    onGoalChange: onGoalChange,
                    onConstraintsChange: onConstraintsChange,
                    onAcceptanceCriteriaChange: onAcceptanceCriteriaChange
                )
                .id(editorIdentity(for: draft))
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
                    .disabled(!canCreate(draft))
                    .opacity(canCreate(draft) ? 1 : 0.55)
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

    private func canCreate(_ draft: CodexTaskDraft?) -> Bool {
        guard let draft else { return false }
        do {
            try CodexTaskFileWriter().validate(draft)
            return true
        } catch {
            return false
        }
    }

    private func editorIdentity(for draft: CodexTaskDraft) -> String {
        [
            draft.sourcePath,
            draft.sourceLine.map(String.init) ?? "",
            draft.sourceEndLine.map(String.init) ?? "",
            draft.sourceBlock ?? "",
            draft.sourceExcerpt
        ].joined(separator: "|")
    }
}

private struct EditableCodexTaskDraftView: View {
    let draft: CodexTaskDraft
    var onTitleChange: (String) -> Void
    var onGoalChange: (String) -> Void
    var onConstraintsChange: (String) -> Void
    var onAcceptanceCriteriaChange: (String) -> Void

    @State private var titleText: String
    @State private var goalText: String
    @State private var constraintsText: String
    @State private var acceptanceCriteriaText: String

    init(
        draft: CodexTaskDraft,
        onTitleChange: @escaping (String) -> Void,
        onGoalChange: @escaping (String) -> Void,
        onConstraintsChange: @escaping (String) -> Void,
        onAcceptanceCriteriaChange: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.onTitleChange = onTitleChange
        self.onGoalChange = onGoalChange
        self.onConstraintsChange = onConstraintsChange
        self.onAcceptanceCriteriaChange = onAcceptanceCriteriaChange
        _titleText = State(initialValue: draft.title)
        _goalText = State(initialValue: draft.goal)
        _constraintsText = State(initialValue: draft.constraints.map { "- \($0)" }.joined(separator: "\n"))
        _acceptanceCriteriaText = State(initialValue: draft.acceptanceCriteria.map { "- [ ] \($0)" }.joined(separator: "\n"))
    }

    var body: some View {
        editableTextField("Title", value: $titleText, onChange: onTitleChange)
        editableTextArea("Goal", value: $goalText, lines: 3, onChange: onGoalChange)
        editableTextArea("Constraints", value: $constraintsText, lines: 4, onChange: onConstraintsChange)
        editableTextArea(
            "Acceptance Criteria",
            value: $acceptanceCriteriaText,
            lines: 5,
            onChange: onAcceptanceCriteriaChange
        )
        readOnlyField("Source", value: sourceLabel(for: draft), mono: true)
        readOnlyField("Excerpt", value: draft.sourceExcerpt, lines: 4, mono: true)
        readOnlyField("File", value: draft.suggestedFilePath, mono: true)
        readOnlyField("Markdown", value: draft.markdown(), lines: 8, mono: true)
    }

    private func editableTextField(
        _ label: String,
        value: Binding<String>,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            TextField(
                "",
                text: Binding(
                    get: { value.wrappedValue },
                    set: {
                        value.wrappedValue = $0
                        onChange($0)
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
        }
    }

    private func editableTextArea(
        _ label: String,
        value: Binding<String>,
        lines: Int,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            TextEditor(
                text: Binding(
                    get: { value.wrappedValue },
                    set: {
                        value.wrappedValue = $0
                        onChange($0)
                    }
                )
            )
            .font(.system(size: 13))
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 21, alignment: .topLeading)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
        }
    }

    private func readOnlyField(_ label: String, value: String, lines: Int = 1, mono: Bool = false) -> some View {
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

    private func sourceLabel(for draft: CodexTaskDraft) -> String {
        if let line = draft.sourceLine {
            if let endLine = draft.sourceEndLine, endLine > line {
                return "\(draft.sourcePath):\(line)-\(endLine)"
            }
            return "\(draft.sourcePath):\(line)"
        }
        return draft.sourcePath
    }
}
