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
        context.coordinator.cardController.attach(
            textView: textView,
            layoutManager: layoutManager,
            renderController: context.coordinator.controller
        )
        let appState = appState
        context.coordinator.cardController.contentProvider = { cardContext in
            AnyView(DynamicBlockCardView(context: cardContext, appState: appState))
        }
        context.coordinator.controller.styleAll()
        #if DEBUG
        context.coordinator.controller.runBenchmarkIfRequested()
        #endif

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
        Coordinator(text: $text, selection: $selection, sourcePath: sourcePath, appState: appState)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selection: SelectionModel
        var sourcePath: String
        let controller = LiveRenderController()
        let cardController = CardIslandController()
        private let appState: AppState

        init(text: Binding<String>, selection: Binding<SelectionModel>, sourcePath: String, appState: AppState) {
            self._text = text
            self._selection = selection
            self.sourcePath = sourcePath
            self.appState = appState
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateSelection(from: textView, range: textView.selectedRange())
            // A checkbox toggle restyles only its own line and skips the debounced full pass;
            // every other edit takes the normal edited-paragraph path.
            if let liveTextView = textView as? LiveTextView,
               let toggledLocation = liveTextView.consumePendingToggleLocation() {
                controller.styleToggledLine(at: toggledLocation)
            } else {
                controller.styleEditedParagraph()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateSelection(from: textView, range: textView.selectedRange())
            controller.reconcileConcealment()
            cardController.selectionDidChange()
        }

        func updateSelection(from textView: NSTextView, range: NSRange) {
            let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
            selection = SelectionModel(
                selectedText: selected,
                sourcePath: sourcePath,
                selectedRange: range,
                cursorLocation: range.location
            )
            // Published for the Codex popover to anchor at the selection (or caret when
            // empty). firstRect(forCharacterRange:) is the sanctioned exception to the
            // no-layoutManager rule, for this one purpose only (packet contract, P3-codex).
            appState.codexAnchorScreenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        }
    }
}
