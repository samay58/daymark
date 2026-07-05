import AppKit
import SwiftUI
import DaymarkCore

/// The receipt card shown after a Codex task file is created (spec "Codex composer and
/// receipts"). App chrome, never note content: rises in at the column's bottom-right and
/// persists until "Done" is pressed. "Create context bundle" expands the same card into the
/// existing bundle-preview flow rather than opening a second surface.
struct ReceiptCard: View {
    let appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyConfirmed = false

    var body: some View {
        if let receipt = appState.codexReceipt {
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

    @ViewBuilder
    private func card(for receipt: CodexReceiptState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isCodexBundleExpanded {
                bundleContent
            } else {
                receiptContent(receipt)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: appState.isCodexBundleExpanded)
    }

    private func receiptContent(_ receipt: CodexReceiptState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.taskTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(receipt.relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            HStack(spacing: 8) {
                Button("Reveal in Finder") { reveal(receipt) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(copyConfirmed ? "Copied" : "Copy path") { copyPath(receipt) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: 8) {
                Button("Create context bundle") { appState.expandCodexReceiptToBundle() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Done") { appState.dismissCodexReceipt() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var bundleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context Bundle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            if let bundle = appState.codexContextBundle {
                ReadOnlyField(label: "Task", value: bundle.taskRelativePath, mono: true)
                ReadOnlyField(label: "File", value: bundle.suggestedFilePath, mono: true)
                ReadOnlyField(label: "Markdown", value: bundle.markdown(), lines: 6, mono: true)
            }

            if let message = appState.codexContextBundleMessage {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Approve") { appState.createCodexContextBundle() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!appState.canCreateCodexContextBundle)
                    .opacity(appState.canCreateCodexContextBundle ? 1 : 0.55)
                Button("Cancel") { appState.cancelCodexBundlePreview() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done") { appState.dismissCodexReceipt() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func reveal(_ receipt: CodexReceiptState) {
        let url = appState.workspaceRoot.expandedURL.appendingPathComponent(receipt.relativePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ receipt: CodexReceiptState) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(receipt.relativePath, forType: .string)
        copyConfirmed = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copyConfirmed = false
        }
    }
}
