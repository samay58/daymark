import AppKit
import SwiftUI

/// The live editing surface for Today (ADR-001: AppKit `NSTextView` wrapped for SwiftUI).
/// The buffer updates instantly on every keystroke; persistence, indexing, and styling all
/// happen after the change, never in its path. Markdown stays the source of truth: only
/// display attributes are applied, so `textView.string` is always the literal text on disk.
struct NSTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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
        textView.typingAttributes = MarkdownHighlighter.baseAttributes()
        textView.textContainer?.widthTracksTextView = true

        MarkdownHighlighter.highlight(textView.textStorage ?? NSTextStorage())

        // Make the writing surface ready to type the moment Today appears.
        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }

        // External reload (file watcher) or a programmatic change: replace and restyle,
        // keeping the caret within bounds.
        let previousSelection = textView.selectedRange()
        textView.string = text
        MarkdownHighlighter.highlight(textView.textStorage ?? NSTextStorage())
        let clamped = min(previousSelection.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            if let storage = textView.textStorage {
                MarkdownHighlighter.highlight(storage)
            }
        }
    }
}
