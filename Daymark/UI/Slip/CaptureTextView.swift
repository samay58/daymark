import AppKit
import SwiftUI

/// A multiline plain-text capture field backed by AppKit so capture keys behave as the spec
/// requires (ADR-001 already commits to AppKit text): Return saves, Shift+Return inserts a
/// newline, Command+Return appends to Today, Command+Shift+T promotes to a task, Escape cancels.
/// SwiftUI `TextEditor` cannot separate Return-saves from Shift+Return-newline.
struct CaptureTextView: NSViewRepresentable {
    @Binding var text: String
    var onSave: (String) -> Void
    var onAppendToday: (String) -> Void
    var onPromoteTask: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CaptureNSTextView()
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(DesignTokens.textPrimary)
        textView.insertionPointColor = NSColor(DesignTokens.accent)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextView

        init(parent: CaptureTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// NSTextView that routes capture shortcuts to the SwiftUI layer and lets every other key,
/// including Shift+Return for a newline, fall through to standard text editing.
final class CaptureNSTextView: NSTextView {
    weak var coordinator: CaptureTextView.Coordinator?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let isT = event.keyCode == 17

        if isReturn {
            if command {
                coordinator?.parent.onAppendToday(string)
            } else if shift {
                super.keyDown(with: event)
            } else {
                coordinator?.parent.onSave(string)
            }
            return
        }
        if event.keyCode == 53 {
            coordinator?.parent.onCancel()
            return
        }
        if command, shift, isT {
            coordinator?.parent.onPromoteTask(string)
            return
        }
        super.keyDown(with: event)
    }
}
