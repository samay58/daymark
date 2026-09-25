import AppKit
import DaymarkCore

final class LiveTextView: NSTextView {
    var onOpenPalette: ((String) -> Void)?
    weak var controller: LiveRenderController?
    weak var cardController: CardIslandController?

    private var animatingBoxLocation: Int?
    private var animationProgress: CGFloat = 1
    private var animationTask: Task<Void, Never>?
    private var hoveredWikilinkRange: NSRange?

    /// Set just before a checkbox toggle fires `didChangeText`, so the delegate restyles the
    /// toggled line without scheduling the full-document pass. Consumed by the coordinator.
    private var pendingToggle = false

    func consumePendingToggle() -> Bool {
        defer { pendingToggle = false }
        return pendingToggle
    }

    // MARK: - Geometry

    func boundingRect(for range: NSRange) -> CGRect? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else {
            return nil
        }
        var union: CGRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        guard let rect = union else { return nil }
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    func visibleCharacterRange() -> NSRange {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else {
            return NSRange(location: 0, length: (string as NSString).length)
        }
        let location = contentManager.offset(from: contentManager.documentRange.location, to: viewport.location)
        let length = contentManager.offset(from: viewport.location, to: viewport.endLocation)
        return NSRange(location: max(0, location), length: max(0, length))
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        cardController?.repositionCards()
    }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let controller else { return }
        let visible = visibleCharacterRange()
        for token in controller.cachedTokens.inlineTokens where token.kind == .tag {
            guard NSIntersectionRange(token.range, visible).length > 0 else { continue }
            if let glyphRect = boundingRect(for: token.range) {
                LiveDecorationRenderer.drawTagPillBackground(in: glyphRect)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let controller else { return }
        let visible = visibleCharacterRange()
        let selection = selectedRange()
        let ns = string as NSString

        for line in controller.cachedTokens.lines {
            guard case .task(let done, _, let boxRange, _) = line.kind else { continue }
            guard NSIntersectionRange(boxRange, visible).length > 0 else { continue }
            let alpha = controller.overlayAlpha(forRangeAt: boxRange.location, revealedAtRest: LiveRenderController.shouldReveal(boxRange, selection: selection))
            guard alpha > 0.01 else { continue }
            guard let boxRect = boundingRect(for: boxRange) else { continue }
            let progress = boxRange.location == animatingBoxLocation ? animationProgress : 1
            LiveDecorationRenderer.drawCheckbox(in: boxRect, done: done, progress: progress, alpha: alpha)
        }

        for token in controller.cachedTokens.inlineTokens {
            guard case .dueDate(let display) = token.kind else { continue }
            guard NSIntersectionRange(token.range, visible).length > 0, Self.isValid(token.range, in: ns) else { continue }
            let alpha = controller.overlayAlpha(forRangeAt: token.range.location, revealedAtRest: LiveRenderController.shouldReveal(token.range, selection: selection))
            guard alpha > 0.01 else { continue }
            guard let glyphRect = boundingRect(for: token.range) else { continue }
            let fill = dueTokenIsMidLine(token.range, in: ns) ? glyphRect.width : nil
            LiveDecorationRenderer.drawDuePill(in: glyphRect, display: display, fillToWidth: fill, alpha: alpha)
        }
    }

    /// True when non-whitespace follows the due token on its own line. Such a mid-line pill fills
    /// the concealed literal's footprint so no trailing gap shows; an end-of-line pill stays snug.
    private func dueTokenIsMidLine(_ range: NSRange, in ns: NSString) -> Bool {
        let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: range.location, length: 0)))
        var index = NSMaxRange(range)
        while index < lineEnd {
            let ch = ns.character(at: index)
            if ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D { return true }
            index += 1
        }
        return false
    }

    // MARK: - Hit testing

    private enum Hit {
        case checkbox(index: Int)
        case tag(NSRange)
        case wikilink(NSRange)
        case url(NSRange)
    }

    /// The interactive token under `point`, read from the controller's cache. Every cached range
    /// is checked against the current text before use: the cache can trail the buffer briefly,
    /// and reading a stale range out of bounds raises, which would lose unsaved typing.
    private func hit(at point: NSPoint) -> Hit? {
        guard let controller else { return nil }
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard index >= 0, index <= ns.length else { return nil }
        let tokens = controller.cachedTokens
        for line in tokens.lines {
            guard case .task(_, _, let boxRange, _) = line.kind else { continue }
            if NSLocationInRange(index, boxRange), Self.isValid(boxRange, in: ns) { return .checkbox(index: index) }
        }
        for token in tokens.inlineTokens where NSLocationInRange(index, token.range) {
            guard Self.isValid(token.range, in: ns) else { continue }
            switch token.kind {
            case .tag: return .tag(token.range)
            case .wikilink: return .wikilink(token.range)
            case .url: return .url(token.range)
            default: continue
            }
        }
        return nil
    }

    private static func isValid(_ range: NSRange, in ns: NSString) -> Bool {
        range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= ns.length
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        let ns = string as NSString
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .checkbox(let index):
            // Only take the click from caret placement if a toggle happens, so a task
            // lookalike inside a fence does not swallow it.
            if let edit = TaskCheckboxToggler.toggleEdit(in: string, atLineContaining: index) {
                applyToggle(edit)
                return
            }
        case .tag(let range):
            onOpenPalette?(ns.substring(with: range))
            return
        case .wikilink(let range):
            onOpenPalette?(wikilinkName(ns.substring(with: range)))
            return
        case .url(let range):
            if let url = URL(string: ns.substring(with: range)) {
                NSWorkspace.shared.open(url)
                return
            }
        case nil:
            break
        }
        super.mouseDown(with: event)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Require exactly Command, not any modifier combination that happens to include it;
        // Cmd-Shift-Return and Cmd-Option-Return must reach super instead.
        let isExactCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if isExactCommand, event.keyCode == 36 || event.keyCode == 76 {
            if let edit = TaskCheckboxToggler.toggleEdit(in: string, atLineContaining: selectedRange().location) {
                applyToggle(edit)
            }
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Toggle path

    private func applyToggle(_ edit: TaskCheckboxToggler.Edit) {
        let range = edit.range
        guard shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        let becomingDone = edit.replacement == "x"
        pendingToggle = true
        textStorage?.replaceCharacters(in: range, with: edit.replacement)
        didChangeText()
        // The toggled character is the box interior, one past the box's start.
        if becomingDone {
            startCheckAnimation(atBoxLocation: range.location - 1)
        } else {
            cancelAnimation()
        }
    }

    private func startCheckAnimation(atBoxLocation location: Int) {
        cancelAnimation()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            animatingBoxLocation = nil
            animationProgress = 1
            return
        }
        animatingBoxLocation = location
        animationProgress = 0
        animationTask = Task { @MainActor [weak self] in
            await EditorMotion.runFrames { elapsed in
                let fraction = min(1, elapsed / 0.14)
                self?.animationProgress = EditorMotion.easeOut(CGFloat(fraction))
                self?.invalidateBox(location)
                return fraction < 1
            }
            // A cancelled run must not reset state that a newer animation now owns.
            if Task.isCancelled { return }
            self?.animationProgress = 1
            self?.animatingBoxLocation = nil
            self?.invalidateBox(location)
        }
    }

    private func cancelAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animatingBoxLocation = nil
        animationProgress = 1
    }

    private func invalidateBox(_ location: Int) {
        guard location >= 0, location + 3 <= (string as NSString).length else { return }
        if let rect = boundingRect(for: NSRange(location: location, length: 3)) {
            setNeedsDisplay(rect.insetBy(dx: -4, dy: -4))
        } else {
            needsDisplay = true
        }
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .checkbox, .tag, .url:
            // The checkbox is a toggle target like pills and links, so it gets the hand too.
            clearHover()
            NSCursor.pointingHand.set()
        case .wikilink(let range):
            setWikilinkHover(range)
            NSCursor.pointingHand.set()
        case nil:
            clearHover()
            NSCursor.iBeam.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }

    private func setWikilinkHover(_ range: NSRange) {
        guard hoveredWikilinkRange != range else { return }
        clearHover()
        hoveredWikilinkRange = range
        textStorage?.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    }

    private func clearHover() {
        guard let range = hoveredWikilinkRange else { return }
        hoveredWikilinkRange = nil
        let length = (string as NSString).length
        guard range.location + range.length <= length else { return }
        textStorage?.removeAttribute(.underlineStyle, range: range)
    }

    // MARK: - Utilities

    private func wikilinkName(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("[[") { name.removeFirst(2) }
        if name.hasSuffix("]]") { name.removeLast(2) }
        return name
    }
}
