import AppKit
import SwiftUI

/// Presents SwiftUI content in a native `NSPopover` pointing at a screen rect, or at this host's
/// bounds when there is none. Mount it once, invisibly; presentation follows `isPresented`, so no
/// other view manages the popover's lifecycle. The popover takes key focus when it opens, so
/// Return and Escape reach it rather than typing into the note. Its size follows the content's
/// ideal size, so the content caps its own width and height.
struct AnchoredPopoverHost<Content: View>: NSViewRepresentable {
    var isPresented: Bool
    var preferredEdge: NSRectEdge
    /// Asked only when the popover opens, never while typing.
    var anchorScreenRect: @MainActor () -> NSRect?
    /// A close the user started (Escape, clicking away). A close caused by `isPresented` turning
    /// false does not call this, since the caller is already in its end state.
    var onUserClose: @MainActor () -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> PopoverAnchorView {
        let view = PopoverAnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.hostDidMoveToWindow(view)
        }
        return view
    }

    func updateNSView(_ nsView: PopoverAnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(host: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var parent: AnchoredPopoverHost
        private var popover: NSPopover?
        private weak var hostRef: NSView?
        private var isClosingProgrammatically = false

        init(parent: AnchoredPopoverHost) {
            self.parent = parent
        }

        func sync(host: NSView) {
            hostRef = host
            if parent.isPresented {
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
            guard popover == nil, parent.isPresented, let host = hostRef, let window = host.window else { return }

            let anchor = parent.anchorScreenRect().map { host.convert(window.convertFromScreen($0), from: nil) } ?? host.bounds
            let hosting = NSHostingController(rootView: parent.content())
            hosting.sizingOptions = [.preferredContentSize]
            let created = NSPopover()
            created.behavior = .semitransient
            created.delegate = self
            created.contentViewController = hosting
            created.show(relativeTo: anchor, of: host, preferredEdge: parent.preferredEdge)
            hosting.view.window?.makeKey()
            popover = created
        }

        func popoverDidClose(_ notification: Notification) {
            let wasProgrammatic = isClosingProgrammatically
            isClosingProgrammatically = false
            popover = nil
            if !wasProgrammatic {
                parent.onUserClose()
            } else if parent.isPresented {
                // Presented again while the close animation ran; attemptPresent skipped it then.
                attemptPresent()
            }
        }
    }
}

final class PopoverAnchorView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}
