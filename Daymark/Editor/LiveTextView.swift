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

    /// Set on the toggled line's start location just before a toggle fires `didChangeText`, so
    /// the delegate routes the change to a targeted single-line restyle instead of the caret's
    /// paragraph plus a full-document pass (Bug 1). Consumed and cleared by the coordinator.
    private(set) var pendingToggleLocation: Int?

    func consumePendingToggleLocation() -> Int? {
        defer { pendingToggleLocation = nil }
        return pendingToggleLocation
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

        for line in controller.cachedTokens.lines {
            guard case .task(let done, _, let boxRange, _) = line.kind else { continue }
            guard NSIntersectionRange(boxRange, visible).length > 0 else { continue }
            if LiveRenderController.shouldReveal(boxRange, selection: selection) { continue }
            guard let boxRect = boundingRect(for: boxRange) else { continue }
            let progress = boxRange.location == animatingBoxLocation ? animationProgress : 1
            LiveDecorationRenderer.drawCheckbox(in: boxRect, done: done, progress: progress)
        }

        for token in controller.cachedTokens.inlineTokens {
            guard case .dueDate(let display) = token.kind else { continue }
            guard NSIntersectionRange(token.range, visible).length > 0 else { continue }
            if LiveRenderController.shouldReveal(token.range, selection: selection) { continue }
            guard let glyphRect = boundingRect(for: token.range) else { continue }
            LiveDecorationRenderer.drawDuePill(in: glyphRect, display: display)
        }
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let text = string
        let ns = text as NSString
        guard index >= 0, index <= ns.length, let controller else {
            super.mouseDown(with: event)
            return
        }
        let tokens = controller.cachedTokens

        for line in tokens.lines {
            guard case .task(_, _, let boxRange, _) = line.kind else { continue }
            guard index >= boxRange.location, index < boxRange.location + boxRange.length else { continue }
            // Hit a checkbox glyph target. Only steal the click (skip caret placement) if a
            // toggle actually happens; otherwise this falls through to super.mouseDown below
            // (Finding 2: a fence task-lookalike with no real checkbox must not eat the click).
            if let edit = TaskCheckboxToggler.toggleEdit(in: text, atLineContaining: index) {
                applyToggle(edit)
                return
            }
            break
        }

        tokenLoop: for token in tokens.inlineTokens {
            guard index >= token.range.location, index < token.range.location + token.range.length else { continue }
            switch token.kind {
            case .tag:
                onOpenPalette?(ns.substring(with: token.range))
                return
            case .wikilink:
                onOpenPalette?(wikilinkName(ns.substring(with: token.range)))
                return
            case .url:
                if let url = URL(string: ns.substring(with: token.range)) {
                    NSWorkspace.shared.open(url)
                    return
                }
                break tokenLoop
            default:
                break tokenLoop
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Finding 3: require exactly Command, not any modifier combination that happens to
        // include it (Cmd-Shift-Return, Cmd-Option-Return, etc. must reach super instead).
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
        // The box interior sits at boxRange.location + 1, so the box (and the line) start one
        // character earlier. The delegate uses this to restyle just the toggled line.
        pendingToggleLocation = range.location - 1
        textStorage?.replaceCharacters(in: range, with: edit.replacement)
        didChangeText()
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
            let start = CACurrentMediaTime()
            let duration = 0.14
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
                let fraction = min(1, elapsed / duration)
                self?.animationProgress = LiveTextView.easeOut(CGFloat(fraction))
                self?.invalidateBox(location)
                if fraction >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
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

    private static func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
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
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard index >= 0, index <= ns.length, let controller else {
            clearHover()
            NSCursor.iBeam.set()
            return
        }
        // Bug 4: the checkbox glyph is an interactive toggle target (same as pills and links),
        // so the pointer becomes a pointing hand over its box range.
        for line in controller.cachedTokens.lines {
            guard case .task(_, _, let boxRange, _) = line.kind else { continue }
            guard index >= boxRange.location, index < boxRange.location + boxRange.length else { continue }
            clearHover()
            NSCursor.pointingHand.set()
            return
        }
        for token in controller.cachedTokens.inlineTokens {
            guard index >= token.range.location, index < token.range.location + token.range.length else { continue }
            switch token.kind {
            case .tag, .url:
                clearHover()
                NSCursor.pointingHand.set()
                return
            case .wikilink:
                setWikilinkHover(token.range)
                NSCursor.pointingHand.set()
                return
            default:
                break
            }
        }
        clearHover()
        NSCursor.iBeam.set()
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
