import AppKit
import SwiftUI
import DaymarkCore

/// Presents the approval step for `/daymark` lines that have no generated region yet. Nothing
/// is written until Insert; any close the user starts (Cancel, Escape, clicking away) drops the
/// inserts. Same presentation as the Codex popover: a native `NSPopover` anchored at the first
/// new command line, falling back to this host's bounds when the editor gives no rect.
struct NewDynamicBlocksPopoverHost: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> PopoverAnchorView {
        let view = PopoverAnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.hostDidMoveToWindow(view)
        }
        return view
    }

    func updateNSView(_ nsView: PopoverAnchorView, context: Context) {
        context.coordinator.sync(host: nsView, appState: appState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private weak var hostRef: NSView?
        private weak var appStateRef: AppState?
        private var isClosingProgrammatically = false

        func sync(host: NSView, appState: AppState) {
            hostRef = host
            appStateRef = appState
            if appState.isNewDynamicBlocksPopoverPresented {
                attemptPresent()
            } else if let popover {
                isClosingProgrammatically = true
                popover.performClose(nil)
            }
        }

        func hostDidMoveToWindow(_ host: NSView) {
            hostRef = host
            attemptPresent()
        }

        private func attemptPresent() {
            guard popover == nil else { return }
            guard let appState = appStateRef, appState.isNewDynamicBlocksPopoverPresented else { return }
            guard let host = hostRef, let window = host.window else { return }

            let anchor: NSRect
            if let screenRect = appState.newDynamicBlocksAnchorScreenRect() {
                anchor = host.convert(window.convertFromScreen(screenRect), from: nil)
            } else {
                anchor = host.bounds
            }

            let hosting = NSHostingController(rootView: NewDynamicBlocksForm(appState: appState))
            hosting.sizingOptions = [.preferredContentSize]
            let created = NSPopover()
            created.behavior = .semitransient
            created.delegate = self
            created.contentViewController = hosting
            created.show(relativeTo: anchor, of: host, preferredEdge: .minY)
            // Take key focus so Return reaches Insert instead of typing a newline into the note,
            // which would also make the preview stale.
            hosting.view.window?.makeKey()
            popover = created
        }

        // A close we did not start (Escape, clicking away) is an implicit Cancel.
        func popoverDidClose(_ notification: Notification) {
            let wasProgrammatic = isClosingProgrammatically
            isClosingProgrammatically = false
            popover = nil
            if !wasProgrammatic {
                appStateRef?.cancelNewDynamicBlocks()
            }
        }
    }
}

private struct NewDynamicBlocksForm: View {
    let appState: AppState

    private static let width: CGFloat = 400
    private static let maxBodyHeight: CGFloat = 320

    private var blocks: [NewDynamicBlock] { appState.dynamicBlockSession?.newBlocks ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(blocks.count == 1 ? "Insert new block" : "Insert \(blocks.count) new blocks")
                .font(.system(size: 15, weight: .semibold))
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
                    Task { await appState.insertNewDynamicBlocks() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.canInsertNewDynamicBlocks)
                .opacity(appState.canInsertNewDynamicBlocks ? 1 : 0.55)
                Button("Cancel") { appState.cancelNewDynamicBlocks() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(appState.isApplyingDynamicBlocks)
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.clear)
    }

    private var statusMessage: String? {
        if let error = appState.newDynamicBlocksError { return error }
        return appState.isDynamicBlockPreviewStale ? DynamicBlockCopy.stale : nil
    }

    private func blockPreview(_ block: NewDynamicBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(block.title)
                    .font(.system(size: 12, weight: .medium))
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
