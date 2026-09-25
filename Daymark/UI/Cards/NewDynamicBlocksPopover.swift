import AppKit
import SwiftUI
import DaymarkCore

/// Presents the approval step for `/daymark` lines that have no generated region yet. Nothing
/// is written until Insert; any close the user starts (Cancel, Escape, clicking away) drops the
/// inserts. The popover points at the first new command line, or at this host (the day header)
/// when the editor gives no rect.
struct NewDynamicBlocksPopoverHost: View {
    let appState: AppState

    var body: some View {
        AnchoredPopoverHost(
            isPresented: appState.dynamicBlocks.isNewBlocksPopoverPresented,
            preferredEdge: .minY,
            anchorScreenRect: {
                appState.dynamicBlocks.newBlocksAnchorRange.flatMap { appState.screenRect(forCharacterRange: $0) }
            },
            onUserClose: { appState.dynamicBlocks.cancelNewBlocks() }
        ) {
            NewDynamicBlocksForm(model: appState.dynamicBlocks)
        }
    }
}

private struct NewDynamicBlocksForm: View {
    let model: DynamicBlockRefreshModel

    private static let width: CGFloat = 400
    private static let maxBodyHeight: CGFloat = 320

    private var blocks: [NewDynamicBlock] { model.session?.newBlocks ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(blocks.count == 1 ? "Insert new block" : "Insert \(blocks.count) new blocks")
                .font(DesignType.panelTitle)
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(blocks) { block in
                        blockPreview(block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.maxBodyHeight)

            if let message = statusMessage {
                Text(message)
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            HStack(spacing: 8) {
                Button("Insert") {
                    Task { await model.insertNewBlocks() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canInsertNewBlocks)
                Button("Cancel") { model.cancelNewBlocks() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isApplying)
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.clear)
    }

    private var statusMessage: String? {
        if let error = model.newBlocksError { return error }
        return model.isPreviewStale ? DynamicBlockCopy.stale : nil
    }

    private func blockPreview(_ block: NewDynamicBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(block.title)
                    .font(DesignType.label)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer(minLength: 8)
                Text(DynamicBlockCopy.summary(for: block.patch))
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            CardMarkdownText(markdown: block.patch.generatedMarkdown)
                .equatable()
        }
    }
}
