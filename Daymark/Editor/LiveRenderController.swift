import AppKit
import DaymarkCore

@MainActor
final class LiveRenderController {
    static let bodySize: CGFloat = 16

    weak var textView: LiveTextView?
    weak var cardController: CardIslandController?
    private var fullPassTask: Task<Void, Never>?

    /// The authoritative token cache, refreshed wholesale by `styleAll()` and patched
    /// incrementally by `styleEditedParagraph()`. `draw`/`drawBackground`/`mouseDown`/
    /// `mouseMoved` on the text view consult this and never call the scanner themselves
    /// (Finding 5: those run once per event, sometimes many times per second).
    private(set) var cachedTokens = NoteTokens(lines: [], inlineTokens: [], regions: [])
    /// Bumped every time `cachedTokens` changes, so callers can detect a stale read across an
    /// await boundary without re-diffing the tokens themselves.
    private(set) var textVersion = 0
    /// Fence state entering each line, as of the last full pass: `(line start location, fence
    /// state before that line is consumed)`, sorted ascending by location. Lets a same-line
    /// keystroke look up its fence state in O(log n) instead of walking the document (Finding 1's
    /// decision rule measured that walk at several ms on a 5k-line note, over the 0.5ms budget).
    /// Kept in sync incrementally in `mergeIntoCache`: a non-fence-marker edit cannot change any
    /// fence transition (fence-marker edits take the immediate full-pass path instead), so only
    /// the locations after the edit need shifting, never the fence values.
    private var lineFenceStates: [(location: Int, fence: MarkdownFenceScanner)] = []

    func attach(_ textView: LiveTextView) {
        self.textView = textView
        textView.controller = self
    }

    static func baseFont() -> NSFont { .systemFont(ofSize: bodySize) }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 8
        return style
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont(),
            .foregroundColor: NSColor(DesignTokens.textPrimary),
            .paragraphStyle: paragraphStyle()
        ]
    }

    func styleAll() {
        guard let storage = textView?.textStorage else { return }
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let started = CFAbsoluteTimeGetCurrent()
        let tokens = NoteTokenScanner.scan(text)
        apply(tokens, to: storage, in: full)
        applyEmphasis(storage, tokens: tokens, in: full)
        applyConcealment(tokens: tokens, selection: currentSelection(), storage: storage)
        cachedTokens = tokens
        lineFenceStates = Self.fenceStates(for: text)
        textVersion += 1
        logFull(CFAbsoluteTimeGetCurrent() - started, lineCount: tokens.lines.count)
        textView?.needsDisplay = true
        cardController?.regionsDidChange()
    }

    func styleEditedParagraph() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string
        let ns = text as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        let paragraph = ns.lineRange(for: NSRange(location: caret, length: 0))

        // Opening or closing a fence reclassifies every line after it. Correct immediately
        // (a full pass) instead of waiting out the debounce, so there is no visible window
        // where stale checkbox/pill/tag decorations show up inside (or outside) the fence.
        if containsFenceMarker(ns, in: paragraph) {
            styleAll()
            return
        }

        let started = CFAbsoluteTimeGetCurrent()
        let fence = fenceStateEntering(paragraph.location)
        let tokens = NoteTokenScanner.scanLines(text, in: paragraph, fence: fence)
        apply(tokens, to: storage, in: paragraph)
        applyEmphasis(storage, tokens: tokens, in: paragraph)
        applyConcealment(tokens: tokens, selection: textView.selectedRange(), storage: storage)
        mergeIntoCache(tokens, editedRange: paragraph)
        logSync(CFAbsoluteTimeGetCurrent() - started)
        textView.needsDisplay = true
        scheduleFullPass()
    }

    func reconcileConcealment() {
        guard let textView, let storage = textView.textStorage else { return }
        applyConcealment(tokens: cachedTokens, selection: textView.selectedRange(), storage: storage)
        textView.needsDisplay = true
    }

    // MARK: - Cache maintenance (Finding 5)

    /// One entry per line: `(line start location, fence state entering that line)`. Built with a
    /// single trimmed-prefix walk over the whole document, same shape as the walk
    /// `NoteTokenScanner.scanLines(_:in:)` does internally, but done once per full pass instead
    /// of once per keystroke.
    private static func fenceStates(for text: String) -> [(location: Int, fence: MarkdownFenceScanner)] {
        let ns = text as NSString
        var states: [(location: Int, fence: MarkdownFenceScanner)] = []
        var fence = MarkdownFenceScanner()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { substring, range, _, _ in
            states.append((range.location, fence))
            _ = fence.consume(trimmedLine: leftTrimmed(substring ?? ""))
        }
        return states
    }

    private static func leftTrimmed(_ content: String) -> String {
        var count = 0
        for character in content {
            if character == " " || character == "\t" { count += 1 } else { break }
        }
        return String(content.dropFirst(count))
    }

    /// Fence state entering `location`, found by binary search over `lineFenceStates` (the
    /// largest recorded line-start at or before `location`). O(log n), never walks the document.
    private func fenceStateEntering(_ location: Int) -> MarkdownFenceScanner {
        guard !lineFenceStates.isEmpty else { return MarkdownFenceScanner() }
        var low = 0
        var high = lineFenceStates.count - 1
        var best = MarkdownFenceScanner()
        while low <= high {
            let mid = (low + high) / 2
            if lineFenceStates[mid].location <= location {
                best = lineFenceStates[mid].fence
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    private func containsFenceMarker(_ ns: NSString, in range: NSRange) -> Bool {
        var index = range.location
        let end = range.location + range.length
        while index < end {
            let ch = ns.character(at: index)
            if ch == 0x20 || ch == 0x09 { index += 1; continue }
            guard ch == UInt16(UnicodeScalar("`").value) || ch == UInt16(UnicodeScalar("~").value) else { return false }
            var count = 0
            var probe = index
            while probe < end, ns.character(at: probe) == ch {
                count += 1
                probe += 1
            }
            return count >= 3
        }
        return false
    }

    /// Replaces cached lines/inline tokens whose range falls inside the edited paragraph with
    /// the freshly scanned ones, and shifts everything after the paragraph by the length delta
    /// this edit introduced (a single-line insert/delete moves every later offset by the same
    /// amount). Lines strictly before the paragraph are untouched and need no shifting.
    private func mergeIntoCache(_ tokens: NoteTokens, editedRange: NSRange) {
        let previousLength = cachedTokens.lines.first { $0.range.location == editedRange.location }?.range.length
            ?? editedRange.length
        let delta = editedRange.length - previousLength

        var lines: [NoteTokens.Line] = []
        lines.reserveCapacity(cachedTokens.lines.count)
        for line in cachedTokens.lines {
            if line.range.location < editedRange.location {
                lines.append(line)
            } else if line.range.location > editedRange.location {
                lines.append(delta == 0 ? line : shifted(line, by: delta))
            }
        }
        lines.append(contentsOf: tokens.lines)
        lines.sort { $0.range.location < $1.range.location }

        var inline: [NoteTokens.InlineToken] = []
        inline.reserveCapacity(cachedTokens.inlineTokens.count)
        let staleUpperBound = editedRange.location + max(editedRange.length, previousLength)
        for token in cachedTokens.inlineTokens {
            if token.range.location < editedRange.location {
                inline.append(token)
            } else if token.range.location >= staleUpperBound {
                inline.append(delta == 0 ? token : shifted(token, by: delta))
            }
        }
        inline.append(contentsOf: tokens.inlineTokens)
        inline.sort { $0.range.location < $1.range.location }

        cachedTokens = NoteTokens(lines: lines, inlineTokens: inline, regions: cachedTokens.regions)

        // A non-fence-marker edit cannot open or close a fence (that path goes through
        // `styleAll()` above instead), so every recorded fence value stays correct; only the
        // locations after the edit need to move by the same delta the lines did.
        if delta != 0 {
            lineFenceStates = lineFenceStates.map { entry in
                entry.location > editedRange.location ? (entry.location + delta, entry.fence) : entry
            }
        }
        textVersion += 1
    }

    private func shifted(_ line: NoteTokens.Line, by delta: Int) -> NoteTokens.Line {
        let newRange = shifted(line.range, by: delta)
        let newKind: NoteTokens.LineKind
        switch line.kind {
        case .heading(let level, let markerRange):
            newKind = .heading(level: level, markerRange: shifted(markerRange, by: delta))
        case .task(let done, let markerRange, let boxRange, let textRange):
            newKind = .task(
                done: done,
                markerRange: shifted(markerRange, by: delta),
                boxRange: shifted(boxRange, by: delta),
                textRange: shifted(textRange, by: delta)
            )
        case .bullet(let markerRange):
            newKind = .bullet(markerRange: shifted(markerRange, by: delta))
        case .quote, .commandLine, .fence, .body, .blank:
            newKind = line.kind
        }
        return NoteTokens.Line(range: newRange, kind: newKind)
    }

    private func shifted(_ token: NoteTokens.InlineToken, by delta: Int) -> NoteTokens.InlineToken {
        NoteTokens.InlineToken(range: shifted(token.range, by: delta), kind: token.kind)
    }

    private func shifted(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    private func scheduleFullPass() {
        fullPassTask?.cancel()
        fullPassTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            self?.styleAll()
        }
    }

    private func currentSelection() -> NSRange {
        textView?.selectedRange() ?? NSRange(location: 0, length: 0)
    }

    // MARK: - Attribute application

    private func apply(_ tokens: NoteTokens, to storage: NSTextStorage, in range: NSRange) {
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes(), range: range)
        for line in tokens.lines {
            applyLine(line, storage: storage)
        }
        for token in tokens.inlineTokens {
            applyInline(token, storage: storage)
        }
        storage.endEditing()
    }

    private func applyLine(_ line: NoteTokens.Line, storage: NSTextStorage) {
        switch line.kind {
        case .heading(let level, let markerRange):
            storage.addAttribute(.font, value: Self.headingFont(level: level), range: line.range)
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: markerRange)
        case .task(let done, let markerRange, _, let textRange):
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textTertiary), range: markerRange)
            if done {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textSecondary), range: textRange)
            }
        case .bullet(let markerRange):
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: markerRange)
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textSecondary), range: line.range)
            italicize(storage, range: line.range)
            tintQuoteMarker(storage, lineRange: line.range)
        case .commandLine:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: line.range)
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: line.range)
        case .fence, .body, .blank:
            break
        }
    }

    private func applyInline(_ token: NoteTokens.InlineToken, storage: NSTextStorage) {
        switch token.kind {
        case .tag:
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accentDeep), range: token.range)
        case .wikilink:
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: token.range)
            tintWikilinkBrackets(storage, range: token.range)
        case .url:
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: token.range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: token.range)
        case .dueDate, .codeSpan, .bold, .italic:
            break
        }
    }

    private func applyEmphasis(_ storage: NSTextStorage, tokens: NoteTokens, in range: NSRange) {
        let fenceRanges = tokens.lines.compactMap { line -> NSRange? in
            if case .fence = line.kind { return line.range }
            return nil
        }
        let text = storage.string
        enumerate(Patterns.inlineCode, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular), range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: match.range)
        }
        enumerate(Patterns.bold, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            convertFont(storage, range: match.range, trait: .boldFontMask)
        }
        enumerate(Patterns.italic, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            convertFont(storage, range: match.range, trait: .italicFontMask)
        }
    }

    // MARK: - Concealment

    private func applyConcealment(tokens: NoteTokens, selection: NSRange, storage: NSTextStorage) {
        storage.beginEditing()
        for line in tokens.lines {
            guard case .task(let done, _, let boxRange, _) = line.kind else { continue }
            if Self.shouldReveal(boxRange, selection: selection) {
                let color = done ? NSColor(DesignTokens.textSecondary) : NSColor(DesignTokens.textPrimary)
                storage.addAttribute(.foregroundColor, value: color, range: clamp(boxRange, to: storage))
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: clamp(boxRange, to: storage))
            }
        }
        for token in tokens.inlineTokens {
            guard case .dueDate = token.kind else { continue }
            if Self.shouldReveal(token.range, selection: selection) {
                storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textPrimary), range: clamp(token.range, to: storage))
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: clamp(token.range, to: storage))
            }
        }
        storage.endEditing()
    }

    private func clamp(_ range: NSRange, to storage: NSTextStorage) -> NSRange {
        let length = storage.length
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    /// Finding 4: a zero-length (caret) selection reveals only when the caret sits strictly
    /// inside the range, not merely adjacent to it; a non-empty selection reveals only when it
    /// actually overlaps the range. Shared with `LiveTextView`'s identical decoration-suppression
    /// check so concealment and drawing never disagree about what's "selected".
    static func shouldReveal(_ range: NSRange, selection: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        if selection.length == 0 {
            let caret = selection.location
            return range.location < caret && caret < range.location + range.length
        }
        return NSIntersectionRange(range, selection).length > 0
    }

    // MARK: - Helpers

    private func tintQuoteMarker(_ storage: NSTextStorage, lineRange: NSRange) {
        let ns = storage.string as NSString
        var index = lineRange.location
        let end = lineRange.location + lineRange.length
        while index < end {
            let ch = ns.character(at: index)
            if ch == 0x20 || ch == 0x09 { index += 1; continue }
            if ch == UInt16(UnicodeScalar(">").value) {
                storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: NSRange(location: index, length: 1))
            }
            break
        }
    }

    private func tintWikilinkBrackets(_ storage: NSTextStorage, range: NSRange) {
        guard range.length >= 4 else { return }
        let open = NSRange(location: range.location, length: 2)
        let close = NSRange(location: range.location + range.length - 2, length: 2)
        storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textTertiary), range: open)
        storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textTertiary), range: close)
    }

    private func italicize(_ storage: NSTextStorage, range: NSRange) {
        convertFont(storage, range: range, trait: .italicFontMask)
    }

    private func convertFont(_ storage: NSTextStorage, range: NSRange, trait: NSFontTraitMask) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? Self.baseFont()
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
        }
    }

    private func intersectsFence(_ range: NSRange, _ fences: [NSRange]) -> Bool {
        fences.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 24
        case 2: size = 19
        case 3: size = 17
        default: size = 16
        }
        return .systemFont(ofSize: size, weight: .semibold)
    }

    private func enumerate(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        body: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match { body(match) }
        }
    }

    private enum Patterns {
        static let inlineCode = make("`[^`\\n]+`")
        static let bold = make("\\*\\*[^*\\n]+\\*\\*")
        static let italic = make("(?<![\\*_])_[^_\\n]+_(?![\\*_])")

        private static func make(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [])
        }
    }

    // MARK: - Timing

    private func logSync(_ seconds: Double) {
        #if DEBUG
        NSLog("[Daymark] live sync paragraph restyle: %.3f ms", seconds * 1000)
        #endif
    }

    private func logFull(_ seconds: Double, lineCount: Int) {
        #if DEBUG
        NSLog("[Daymark] live full restyle: %.3f ms (%d lines)", seconds * 1000, lineCount)
        #endif
    }
}
