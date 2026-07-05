import AppKit
import SwiftUI

// The live editing surface for Today (ADR-001: AppKit NSTextView wrapped for SwiftUI).
// The buffer updates instantly on every keystroke; persistence, indexing, and styling all
// happen after the change, never in its path. Markdown stays the source of truth: only
// display attributes and drawn decorations are applied, so textView.string is always the
// literal text on disk.
struct NSTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: SelectionModel
    var sourcePath: String
    @Environment(AppState.self) private var appState

    func makeNSView(context: Context) -> NSScrollView {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container

        let textView = LiveTextView(frame: .zero, textContainer: container)
        assert(textView.textLayoutManager != nil, "LiveTextView must run on TextKit 2")

        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = NSColor(DesignTokens.accent)
        textView.textContainerInset = NSSize(width: 4, height: 12)
        textView.typingAttributes = LiveRenderController.baseAttributes()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onOpenPalette = { [appState] name in
            appState.showCommandPalette(prefill: name)
        }

        context.coordinator.controller.attach(textView)
        context.coordinator.controller.styleAll()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LiveTextView else { return }
        context.coordinator.sourcePath = sourcePath
        textView.onOpenPalette = { [appState] name in
            appState.showCommandPalette(prefill: name)
        }
        guard textView.string != text else { return }

        let previousSelection = textView.selectedRange()
        textView.string = text
        context.coordinator.controller.styleAll()
        let clamped = min(previousSelection.location, (text as NSString).length)
        let range = NSRange(location: clamped, length: 0)
        textView.setSelectedRange(range)
        context.coordinator.updateSelection(from: textView, range: range)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection, sourcePath: sourcePath)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selection: SelectionModel
        var sourcePath: String
        let controller = LiveRenderController()

        init(text: Binding<String>, selection: Binding<SelectionModel>, sourcePath: String) {
            self._text = text
            self._selection = selection
            self.sourcePath = sourcePath
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateSelection(from: textView, range: textView.selectedRange())
            controller.styleEditedParagraph()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateSelection(from: textView, range: textView.selectedRange())
            controller.reconcileConcealment()
        }

        func updateSelection(from textView: NSTextView, range: NSRange) {
            let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
            selection = SelectionModel(
                selectedText: selected,
                sourcePath: sourcePath,
                selectedRange: range,
                cursorLocation: range.location
            )
        }
    }
}
