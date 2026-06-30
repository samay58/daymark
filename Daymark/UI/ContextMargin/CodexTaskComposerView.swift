import SwiftUI
import DaymarkCore

struct CodexTaskComposerView: View {
    let draft: CodexTaskDraft?
    let message: String?
    let canCreate: Bool
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
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.55)
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .marginPanel()
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

struct CodexContextBundlePreviewView: View {
    let taskRelativePath: String?
    let bundle: CodexContextBundle?
    let message: String?
    let canCreate: Bool
    var onPreview: () -> Void
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Context Bundle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            if let bundle {
                ReadOnlyField(label: "Task", value: bundle.taskRelativePath, mono: true)
                ReadOnlyField(label: "File", value: bundle.suggestedFilePath, mono: true)
                ReadOnlyField(label: "Markdown", value: bundle.markdown(), lines: 10, mono: true)
            } else if let taskRelativePath {
                ReadOnlyField(label: "Task", value: taskRelativePath, mono: true)
            }

            if let message {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            if bundle == nil {
                Button("Preview Context Bundle", action: onPreview)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(taskRelativePath == nil)
                    .opacity(taskRelativePath == nil ? 0.55 : 1)
            } else {
                VStack(spacing: 8) {
                    Button("Create Context Bundle", action: onCreate)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.55)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .marginPanel()
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
        ReadOnlyField(label: "Source", value: sourceLabel(for: draft), mono: true)
        ReadOnlyField(label: "Excerpt", value: draft.sourceExcerpt, lines: 4, mono: true)
        ReadOnlyField(label: "File", value: draft.suggestedFilePath, mono: true)
        ReadOnlyField(label: "Markdown", value: draft.markdown(), lines: 8, mono: true)
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
