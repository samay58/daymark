import AppKit
import SwiftUI
import DaymarkCore

/// Hosts the Codex composer as an `NSPopover` anchored at the current selection's screen
/// rect (spec "Codex composer and receipts"). Mounted once, invisibly, in `RootView`;
/// presentation is entirely driven by `AppState.isCodexPopoverPresented` so no other view
/// needs to know about the popover's lifecycle.
struct CodexPopoverHost: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(host: nsView, appState: appState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private weak var appStateRef: AppState?
        private var isClosingProgrammatically = false

        func sync(host: NSView, appState: AppState) {
            appStateRef = appState
            if appState.isCodexPopoverPresented {
                guard popover == nil else { return }
                present(from: host, appState: appState)
            } else if let popover {
                isClosingProgrammatically = true
                popover.performClose(nil)
            }
        }

        private func present(from host: NSView, appState: AppState) {
            guard let window = host.window else { return }
            let screenRect = appState.codexAnchorScreenRect ?? window.frame
            let localRect = host.convert(window.convertFromScreen(screenRect), from: nil)

            let created = NSPopover()
            created.behavior = .semitransient
            created.delegate = self
            created.contentSize = NSSize(width: 380, height: 480)
            created.contentViewController = NSHostingController(rootView: CodexComposerForm(appState: appState))
            created.show(relativeTo: localRect, of: host, preferredEdge: .maxY)
            popover = created
        }

        // Fires for every close, programmatic or user-driven (click outside, Esc). A
        // programmatic close (Create succeeded, or Cancel already ran) has already put
        // AppState in its correct end state; only a close we did not initiate ourselves
        // needs to be treated as an implicit Cancel.
        func popoverDidClose(_ notification: Notification) {
            let wasProgrammatic = isClosingProgrammatically
            isClosingProgrammatically = false
            popover = nil
            if !wasProgrammatic {
                appStateRef?.dismissCodexTaskDraft()
            }
        }
    }
}

/// The Codex composer field set, restyled from the retired margin composer into the
/// selection-anchored popover. Same field set (Title, Goal, Constraints, Acceptance, source,
/// Markdown) and the same collision-safe `AppState` create path. Default state shows only
/// Title, Goal, a compact source chip, and Create/Cancel; Constraints, Acceptance, the full
/// source, and the Markdown preview sit behind the collapsed "Details" disclosure so the fast
/// path stays two fields, not fewer approvals (spec "Codex popover, calmer and faster").
private struct CodexComposerForm: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create Codex Task")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)

                Rectangle().fill(DesignTokens.hairline).frame(height: 1)

                if let draft = appState.codexTaskDraft {
                    CodexDraftFields(
                        draft: draft,
                        onTitleChange: { appState.updateCodexTaskDraftTitle($0) },
                        onGoalChange: { appState.updateCodexTaskDraftGoal($0) },
                        onConstraintsChange: { appState.updateCodexTaskDraftConstraints($0) },
                        onAcceptanceChange: { appState.updateCodexTaskDraftAcceptanceCriteria($0) }
                    )
                    .id(fieldsIdentity(for: draft))
                }

                if let message = appState.codexTaskMessage {
                    Text(message)
                        .font(DesignType.metadata)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle().fill(DesignTokens.hairline).frame(height: 1)

                HStack(spacing: 8) {
                    Button("Create") { appState.createCodexTaskFile() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!appState.canCreateCodexTaskFile)
                        .opacity(appState.canCreateCodexTaskFile ? 1 : 0.55)
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Cancel") { appState.dismissCodexTaskDraft() }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(16)
        }
        .frame(width: 380, height: 480)
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
                area("Acceptance Criteria", text: $acceptanceText, lines: 4, onChange: onAcceptanceChange)
                ReadOnlyField(label: "Source", value: sourceLabel(for: draft), mono: true)
                ReadOnlyField(label: "Excerpt", value: draft.sourceExcerpt, lines: 3, mono: true)
                ReadOnlyField(label: "Markdown", value: draft.markdown(), lines: 6, mono: true)
            }
            .padding(.top, 10)
        } label: {
            Text("Details")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isDetailsExpanded)
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

/// The collapsed default view's stand-in for the full read-only source display: one line,
/// path and line range only, no excerpt. The excerpt reappears under Details.
private struct CodexSourceChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, design: .monospaced))
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
