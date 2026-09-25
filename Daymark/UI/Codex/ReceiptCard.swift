import AppKit
import SwiftUI
import DaymarkCore

/// The receipt shown after a Codex task file is created. App chrome, never note content: it
/// rises in at the column's bottom-right and stays until Done. "Create context bundle" expands
/// this same card into the bundle preview rather than opening a second surface. Everything it
/// shows comes from `CodexFlowModel.receipt`, so the path and the bundle's source always agree.
struct ReceiptCard: View {
    let appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyConfirmed = false

    private var codex: CodexFlowModel { appState.codex }

    var body: some View {
        if let receipt = codex.receipt {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    card(for: receipt)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                }
            }
            .transition(
                reduceMotion
                    ? .identity
                    : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.16)),
                        removal: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.12))
                    )
            )
        }
    }

    private func card(for receipt: CodexFlowModel.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch receipt.bundle {
            case .collapsed:
                receiptContent(receipt.task)
            case .previewing(let bundle, let error):
                bundleContent(bundle, message: error, isError: error != nil)
            case .written(let bundle):
                bundleContent(bundle, message: "Created \(bundle.suggestedFilePath)", isError: false)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .glassSurface()
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: receipt.bundle)
    }

    private func receiptContent(_ task: CreatedCodexTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.draft.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(task.relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            HStack(spacing: 8) {
                Button("Reveal in Finder") { reveal(task.relativePath) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(copyConfirmed ? "Copied" : "Copy path") { copyPath(task.relativePath) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: 8) {
                Button("Create context bundle") { codex.expandReceiptToBundle() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Done") { codex.dismissReceipt() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func bundleContent(_ bundle: CodexContextBundle, message: String?, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context bundle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            ReadOnlyField(label: "Task", value: bundle.taskRelativePath, mono: true)
            ReadOnlyField(label: "File", value: bundle.suggestedFilePath, mono: true)
            ReadOnlyField(label: "Markdown", value: bundle.markdown(), lines: 6, mono: true)

            if let message {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(isError ? DesignTokens.warning : DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Approve") { codex.createBundle() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!codex.canCreateBundle)
                    .opacity(codex.canCreateBundle ? 1 : 0.55)
                Button("Cancel") { codex.collapseBundle() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done") { codex.dismissReceipt() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func reveal(_ relativePath: String) {
        let url = appState.workspaceRoot.expandedURL.appendingPathComponent(relativePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ relativePath: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(relativePath, forType: .string)
        copyConfirmed = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copyConfirmed = false
        }
    }
}
