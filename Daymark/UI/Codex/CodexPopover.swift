import AppKit
import SwiftUI
import DaymarkCore

/// Hosts the Codex composer in a popover pointing at the current selection. Mounted once,
/// invisibly, in `RootView`; the popover is open exactly while the composer has a draft.
struct CodexPopoverHost: View {
    let appState: AppState

    var body: some View {
        AnchoredPopoverHost(
            isPresented: appState.codex.composer != nil,
            preferredEdge: .maxY,
            anchorScreenRect: { appState.screenRect(forCharacterRange: appState.editorSelection.selectedRange) },
            onUserClose: { appState.codex.dismissComposer() }
        ) {
            CodexComposerForm(appState: appState)
        }
    }
}

/// The Codex composer. Title, Goal, a compact source chip, and Create/Cancel by default;
/// Constraints, Acceptance, the full source, and the Markdown preview sit behind a collapsed
/// Details disclosure. Every field stays bound to the same draft either way, so the short form
/// writes exactly what the expanded form would.
private struct CodexComposerForm: View {
    let appState: AppState

    private static let width: CGFloat = 380
    private static let maxHeight: CGFloat = 480

    private var codex: CodexFlowModel { appState.codex }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create Codex task")
                    .font(DesignType.panelTitle)
                    .foregroundStyle(DesignTokens.textPrimary)

                Rectangle().fill(DesignTokens.hairline).frame(height: 1)

                if let composer = codex.composer {
                    CodexDraftFields(
                        draft: composer.draft,
                        onTitleChange: { codex.updateTitle($0) },
                        onGoalChange: { codex.updateGoal($0) },
                        onConstraintsChange: { codex.updateConstraints($0) },
                        onAcceptanceChange: { codex.updateAcceptanceCriteria($0) }
                    )
                    .id(fieldsIdentity(for: composer.draft))

                    if let error = composer.error {
                        Text(error)
                            .font(DesignType.metadata)
                            .foregroundStyle(DesignTokens.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Rectangle().fill(DesignTokens.hairline).frame(height: 1)

                HStack(spacing: 8) {
                    Button("Create") { codex.createTask() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!codex.canCreateTask)
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Cancel") { codex.dismissComposer() }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight)
        .background(Color.clear)
    }

    private func fieldsIdentity(for draft: CodexTaskDraft) -> String {
        [draft.sourcePath, draft.sourceLine.map(String.init) ?? "", draft.sourceExcerpt]
            .joined(separator: "|")
    }
}

private struct CodexDraftFields: View {
    let draft: CodexTaskDraft
    var onTitleChange: (String) -> Void
    var onGoalChange: (String) -> Void
    var onConstraintsChange: (String) -> Void
    var onAcceptanceChange: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleText: String
    @State private var goalText: String
    @State private var constraintsText: String
    @State private var acceptanceText: String
    @State private var isDetailsExpanded = false

    init(
        draft: CodexTaskDraft,
        onTitleChange: @escaping (String) -> Void,
        onGoalChange: @escaping (String) -> Void,
        onConstraintsChange: @escaping (String) -> Void,
        onAcceptanceChange: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.onTitleChange = onTitleChange
        self.onGoalChange = onGoalChange
        self.onConstraintsChange = onConstraintsChange
        self.onAcceptanceChange = onAcceptanceChange
        _titleText = State(initialValue: draft.title)
        _goalText = State(initialValue: draft.goal)
        _constraintsText = State(initialValue: draft.constraints.map { "- \($0)" }.joined(separator: "\n"))
        _acceptanceText = State(initialValue: draft.acceptanceCriteria.map { "- [ ] \($0)" }.joined(separator: "\n"))
    }

    var body: some View {
        field("Title", text: $titleText, onChange: onTitleChange)
        area("Goal", text: $goalText, lines: 3, onChange: onGoalChange)
        CodexSourceChip(label: sourceLabel(for: draft))
        DisclosureGroup(isExpanded: $isDetailsExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                area("Constraints", text: $constraintsText, lines: 3, onChange: onConstraintsChange)
                area("Acceptance criteria", text: $acceptanceText, lines: 4, onChange: onAcceptanceChange)
                ReadOnlyField(label: "Source", value: sourceLabel(for: draft), mono: true)
                ReadOnlyField(label: "Excerpt", value: draft.sourceExcerpt, lines: 3, mono: true)
                ReadOnlyField(label: "Markdown", value: draft.markdown(), lines: 6, mono: true)
            }
            .padding(.top, 10)
        } label: {
            Text("Details")
                .font(DesignType.label)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .animation(reduceMotion ? nil : DesignMotion.panel, value: isDetailsExpanded)
    }

    private func field(_ label: String, text: Binding<String>, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            TextField(
                "",
                text: Binding(
                    get: { text.wrappedValue },
                    set: {
                        text.wrappedValue = $0
                        onChange($0)
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(DesignType.field)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .fieldChrome()
        }
    }

    private func area(_ label: String, text: Binding<String>, lines: Int, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            TextEditor(
                text: Binding(
                    get: { text.wrappedValue },
                    set: {
                        text.wrappedValue = $0
                        onChange($0)
                    }
                )
            )
            .font(DesignType.field)
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 21, alignment: .topLeading)
            // TextEditor carries its own text inset, so its outer padding is smaller than a field's.
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .fieldChrome()
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

/// The collapsed default view's stand-in for the full read-only source display: one line,
/// path and line range only, no excerpt. The excerpt reappears under Details.
private struct CodexSourceChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(DesignType.chipIcon)
            Text(label)
                .font(DesignType.chip)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.pillRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
    }
}
