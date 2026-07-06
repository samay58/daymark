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
    /// `mouseMoved` on the text view consult this and never call the scanner themselves.
    private(set) var cachedTokens = NoteTokens(lines: [], inlineTokens: [], regions: [])
    /// Bumped every time `cachedTokens` changes, so callers can detect a stale read across an
    /// await boundary without re-diffing the tokens themselves.
    private(set) var textVersion = 0
    /// Fence state entering each line, sorted by line start. Same-line edits look up this cached
    /// state in O(log n); edits that can affect fence structure take the full-pass path.
    private var lineFenceStates: [NoteTokenCacheReducer.LineFenceState] = []

    /// The selection the concealment attributes were last reconciled against. A caret move only
    /// flips the reveal state of tokens the caret entered or left, so `reconcileConcealment`
    /// diffs against this instead of rewriting concealment for every token on the note.
    private var lastConcealmentSelection = NSRange(location: 0, length: 0)

    /// In-flight reveal crossfades, keyed by token start location. A caret entering or leaving a
    /// concealed checkbox, due pill, or machine-text run fades its literal text in or out and its
    /// drawn overlay out or in over ~110ms rather than snapping. Reduce Motion bypasses this and
    /// swaps instantly. An edit is authoritative and clears any fade for its range.
    private struct RevealFade {
        var progress: CGFloat
        var target: CGFloat
        var range: NSRange
        var revealedColor: NSColor
        var hasOverlay: Bool
    }
    private var revealFades: [Int: RevealFade] = [:]
    private var revealFadeTask: Task<Void, Never>?

    private static let concealTextPrimary = NSColor(DesignTokens.textPrimary)
    private static let concealTextSecondary = NSColor(DesignTokens.textSecondary)
    private static let concealTextTertiary = NSColor(DesignTokens.textTertiary)

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

        // The incremental paragraph pass already keeps the cache and the applied attributes in
        // sync line by line. This debounced full scan exists to catch cross-line drift (a fence
        // or region marker opened or closed, a multi-line paste). When the fresh scan matches the
        // cache, none of that happened, so the whole-document re-apply is pure waste and
        // reflows nothing new.
        // The scan still runs every debounce, so the reconcile contract is intact; only the
        // redundant re-styling is skipped.
        if tokens == cachedTokens {
            logFull(CFAbsoluteTimeGetCurrent() - started, lineCount: tokens.lines.count)
            return
        }

        apply(tokens, to: storage, in: full)
        applyEmphasis(storage, tokens: tokens, in: full)
        applyConcealment(tokens: tokens, selection: currentSelection(), storage: storage)
        cachedTokens = tokens
        lineFenceStates = NoteTokenCacheReducer.fenceStates(for: text)
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
        if !NoteTokenCacheReducer.canMergeIncrementally(text: text, editedRange: paragraph) {
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

    /// Restyles exactly the paragraph a checkbox toggle changed, and nothing else. A toggle is
    /// a bounded, same-length `[ ]`/`[x]` edit that cannot open or close a fence and cannot
    /// start or end a generated region (the toggler refuses lines inside a region), so there is
    /// no need for the whole-document `styleAll()` a normal edit schedules. Skipping it removes
    /// the debounced full-document `setAttributes` + card reposition that reflows the note under
    /// the toggled line. It also targets the toggled line directly instead of the caret's line,
    /// since a click toggle leaves the caret where it was.
    func styleToggledLine(at location: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let clamped = min(max(0, location), ns.length)
        let paragraph = ns.lineRange(for: NSRange(location: clamped, length: 0))
        let fence = fenceStateEntering(paragraph.location)
        let tokens = NoteTokenScanner.scanLines(storage.string, in: paragraph, fence: fence)
        apply(tokens, to: storage, in: paragraph)
        applyEmphasis(storage, tokens: tokens, in: paragraph)
        applyConcealment(tokens: tokens, selection: textView.selectedRange(), storage: storage)
        mergeIntoCache(tokens, editedRange: paragraph)
        textView.needsDisplay = true
    }

    func reconcileConcealment() {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let previous = lastConcealmentSelection
        lastConcealmentSelection = selection
        guard previous != selection else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var instantOverlayChanged = false
        storage.beginEditing()
        forEachConcealable(cachedTokens) { range, revealedColor, hasOverlay in
            let was = Self.shouldReveal(range, selection: previous)
            let now = Self.shouldReveal(range, selection: selection)
            guard was != now else { return }
            if reduceMotion {
                revealFades[range.location] = nil
                storage.addAttribute(.foregroundColor, value: now ? revealedColor : NSColor.clear, range: clamp(range, to: storage))
                if hasOverlay { instantOverlayChanged = true }
            } else {
                beginFade(range: range, revealedColor: revealedColor, hasOverlay: hasOverlay, target: now ? 1 : 0)
            }
        }
        storage.endEditing()
        if reduceMotion, instantOverlayChanged { textView.needsDisplay = true }
    }

    /// Alpha for a drawn overlay (checkbox, due pill) at `location`, so a reveal crossfade dims
    /// the overlay in step with the literal text fading in. Read by `LiveTextView.draw`.
    func overlayAlpha(forRangeAt location: Int, revealedAtRest: Bool) -> CGFloat {
        if let fade = revealFades[location] {
            return 1 - Self.easeInOut(fade.progress)
        }
        return revealedAtRest ? 0 : 1
    }

    private func forEachConcealable(_ tokens: NoteTokens, _ body: (NSRange, NSColor, Bool) -> Void) {
        for line in tokens.lines {
            guard case .task(let done, _, let boxRange, _) = line.kind else { continue }
            body(boxRange, done ? Self.concealTextSecondary : Self.concealTextPrimary, true)
        }
        for token in tokens.inlineTokens {
            switch token.kind {
            case .dueDate:
                body(token.range, Self.concealTextPrimary, true)
            case .rolloverMarker, .provenance:
                body(token.range, Self.concealTextTertiary, false)
            default:
                break
            }
        }
    }

    private func beginFade(range: NSRange, revealedColor: NSColor, hasOverlay: Bool, target: CGFloat) {
        if var fade = revealFades[range.location] {
            fade.target = target
            fade.range = range
            fade.revealedColor = revealedColor
            fade.hasOverlay = hasOverlay
            revealFades[range.location] = fade
        } else {
            revealFades[range.location] = RevealFade(
                progress: target >= 1 ? 0 : 1,
                target: target,
                range: range,
                revealedColor: revealedColor,
                hasOverlay: hasOverlay
            )
        }
        startRevealFadeTaskIfNeeded()
    }

    private func startRevealFadeTaskIfNeeded() {
        guard revealFadeTask == nil else { return }
        revealFadeTask = Task { @MainActor [weak self] in
            while let self, !self.revealFades.isEmpty {
                self.stepRevealFades()
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { break }
            }
            self?.revealFadeTask = nil
        }
    }

    private func stepRevealFades() {
        guard let textView, let storage = textView.textStorage else { revealFades.removeAll(); return }
        let step: CGFloat = 0.16
        storage.beginEditing()
        for key in Array(revealFades.keys) {
            guard var fade = revealFades[key] else { continue }
            if fade.progress < fade.target {
                fade.progress = min(fade.target, fade.progress + step)
            } else {
                fade.progress = max(fade.target, fade.progress - step)
            }
            let clamped = clamp(fade.range, to: storage)
            if fade.progress == fade.target {
                storage.addAttribute(.foregroundColor, value: fade.target >= 1 ? fade.revealedColor : NSColor.clear, range: clamped)
                revealFades[key] = nil
            } else {
                storage.addAttribute(.foregroundColor, value: fade.revealedColor.withAlphaComponent(Self.easeInOut(fade.progress)), range: clamped)
                revealFades[key] = fade
            }
        }
        storage.endEditing()
        textView.needsDisplay = true
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped < 0.5 ? 2 * clamped * clamped : 1 - pow(-2 * clamped + 2, 2) / 2
    }

    // MARK: - Cache maintenance

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

    /// Delegates pure token, region, and fence-state range maintenance to Core. The controller
    /// keeps ownership of AppKit attributes, reveal fades, and the debounced full-pass reconcile.
    private func mergeIntoCache(_ tokens: NoteTokens, editedRange: NSRange) {
        let result = NoteTokenCacheReducer.merge(
            state: NoteTokenCacheReducer.State(tokens: cachedTokens, lineFenceStates: lineFenceStates),
            rescanned: tokens,
            editedRange: editedRange
        )
        cachedTokens = result.state.tokens
        lineFenceStates = result.state.lineFenceStates
        shiftRevealFades(editStart: editedRange.location, oldParagraphEnd: result.oldParagraphEnd, delta: result.delta)
        textVersion += 1
    }

    private func shiftRevealFades(editStart: Int, oldParagraphEnd: Int, delta: Int) {
        guard !revealFades.isEmpty else { return }
        let ranges = revealFades.map { NoteTokenCacheReducer.KeyedRange(key: $0.key, range: $0.value.range) }
        let shifted = NoteTokenCacheReducer.shiftKeyedRanges(
            ranges,
            editStart: editStart,
            oldParagraphEnd: oldParagraphEnd,
            delta: delta
        )
        var next: [Int: RevealFade] = [:]
        next.reserveCapacity(shifted.count)
        for item in shifted {
            let originalKey = item.key >= oldParagraphEnd + delta ? item.key - delta : item.key
            guard var fade = revealFades[originalKey] else { continue }
            fade.range = item.range
            next[item.key] = fade
        }
        revealFades = next
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
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: line.range)
            storage.addAttribute(.foregroundColor, value: NSColor(DesignTokens.textTertiary), range: line.range)
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
        case .dueDate, .codeSpan, .bold, .italic, .rolloverMarker, .provenance:
            // Machine text (rollover marker, provenance) carries no emphasis of its own; its
            // visibility is owned entirely by `applyConcealment` (clear when hidden, tertiary
            // when revealed), so there is nothing to add here.
            break
        }
    }

    private static let codeEmphasisFont = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
    private static let accentColor = NSColor(DesignTokens.accent)

    private func applyEmphasis(_ storage: NSTextStorage, tokens: NoteTokens, in range: NSRange) {
        let fenceRanges = tokens.lines.compactMap { line -> NSRange? in
            if case .fence = line.kind { return line.range }
            return nil
        }
        let text = storage.string
        // One editing transaction for every emphasis edit in this range. Unbatched, each
        // `addAttribute` ran its own storage fixups and layout notification, which dominates
        // full-document restyles unless the edits are batched.
        storage.beginEditing()
        enumerate(Patterns.inlineCode, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            storage.addAttribute(.font, value: Self.codeEmphasisFont, range: match.range)
            storage.addAttribute(.foregroundColor, value: Self.accentColor, range: match.range)
        }
        enumerate(Patterns.bold, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            convertFont(storage, range: match.range, trait: .boldFontMask)
        }
        enumerate(Patterns.italic, in: text, range: range) { match in
            guard !intersectsFence(match.range, fenceRanges) else { return }
            convertFont(storage, range: match.range, trait: .italicFontMask)
        }
        storage.endEditing()
    }

    // MARK: - Concealment

    /// Sets each concealable token (task box, due pill, and the machine-text rollover/provenance
    /// runs) to its final revealed or clear color for the given selection, and drops any in-flight
    /// reveal fade in that range: an edit is authoritative, so concealment resolves immediately
    /// rather than animating. Only the foreground color changes, never a metric, so a concealed
    /// run cannot alter line height or shift the following line.
    private func applyConcealment(tokens: NoteTokens, selection: NSRange, storage: NSTextStorage) {
        storage.beginEditing()
        forEachConcealable(tokens) { range, revealedColor, _ in
            revealFades[range.location] = nil
            let revealed = Self.shouldReveal(range, selection: selection)
            storage.addAttribute(.foregroundColor, value: revealed ? revealedColor : NSColor.clear, range: clamp(range, to: storage))
        }
        storage.endEditing()
        // Concealment is now resolved for this selection, so a reconcile fired by the same
        // selection change (a keystroke moves the caret and fires both paths) has nothing to
        // animate and returns early instead of re-flipping the just-set tokens.
        lastConcealmentSelection = selection
    }

    private func clamp(_ range: NSRange, to storage: NSTextStorage) -> NSRange {
        let length = storage.length
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    /// A zero-length caret reveals only when it sits strictly inside the range, not merely
    /// adjacent to it. Non-empty selections reveal only when they actually overlap the range.
    /// Shared with `LiveTextView` so concealment and drawing agree about selection state.
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
            storage.addAttribute(.font, value: Self.trait(font, trait), range: sub)
        }
    }

    private struct FontTraitKey: Hashable {
        let name: String
        let size: CGFloat
        let trait: UInt
    }

    nonisolated(unsafe) private static var traitCache: [FontTraitKey: NSFont] = [:]

    /// `NSFontManager.convert` is the dominant cost of the full-document emphasis pass (measured
    /// at hundreds of ms on a 5k-line note): it was called once per bold/italic match. The set of
    /// distinct input fonts is tiny (body plus three heading weights), so memoize the conversions.
    /// Main-actor only, so the unguarded static is safe.
    private static func trait(_ font: NSFont, _ trait: NSFontTraitMask) -> NSFont {
        let key = FontTraitKey(name: font.fontName, size: font.pointSize, trait: trait.rawValue)
        if let hit = traitCache[key] { return hit }
        let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
        traitCache[key] = converted
        return converted
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
        guard !Self.benchmarkRunning else { return }
        NSLog("[Daymark] live sync paragraph restyle: %.3f ms", seconds * 1000)
        #endif
    }

    private func logFull(_ seconds: Double, lineCount: Int) {
        #if DEBUG
        NSLog("[Daymark] live full restyle: %.3f ms (%d lines)", seconds * 1000, lineCount)
        #endif
    }

    // A debug-only latency harness for the keystroke, concealment, and card-reposition paths.
    // It is compiled out of release builds and does nothing unless DAYMARK_BENCH=1. It drives the
    // controller against a 5k-line note (run against a scratch workspace only), and every buffer
    // edit it makes to time the sync path is a matched insert/remove that restores the buffer, so
    // it is a measurement harness, not a render-path mutation of the document.
    #if DEBUG
    nonisolated(unsafe) static var benchmarkRunning = false

    func runBenchmarkIfRequested() {
        guard ProcessInfo.processInfo.environment["DAYMARK_BENCH"] == "1" else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            Self.benchmarkRunning = true
            self?.runBenchmark()
            Self.benchmarkRunning = false
        }
    }

    private func runBenchmark() {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        guard ns.length > 200 else { return }

        var probe = ns.length / 2
        while probe < ns.length {
            let line = ns.lineRange(for: NSRange(location: probe, length: 0))
            if ns.range(of: "due:", options: [], range: line).location != NSNotFound { probe = line.location; break }
            probe = line.location + max(1, line.length)
        }
        let line = ns.lineRange(for: NSRange(location: probe, length: 0))
        let insertLoc = line.location + min(6, max(0, line.length - 1))

        func stats(_ times: [Double]) -> (median: Double, p95: Double) {
            let sorted = times.sorted()
            return (sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)])
        }

        // Incremental cache correctness: after a net-zero edit the cache must still equal a fresh
        // full scan, or a decoration is stale until the next debounced pass.
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: "Z")
        textView.setSelectedRange(NSRange(location: insertLoc + 1, length: 0))
        styleEditedParagraph()
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 1), with: "")
        textView.setSelectedRange(NSRange(location: insertLoc, length: 0))
        styleEditedParagraph()
        NSLog("[Daymark][BENCH] incremental cache equals fresh scan after edit: %@", (NoteTokenScanner.scan(storage.string) == cachedTokens) ? "yes" : "no")

        var syncTimes: [Double] = []
        for _ in 0..<300 {
            textView.setSelectedRange(NSRange(location: insertLoc, length: 0))
            storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: "x")
            textView.setSelectedRange(NSRange(location: insertLoc + 1, length: 0))
            let t = CFAbsoluteTimeGetCurrent()
            styleEditedParagraph()
            syncTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            storage.replaceCharacters(in: NSRange(location: insertLoc, length: 1), with: "")
            styleEditedParagraph()
        }
        let sync = stats(syncTimes)
        NSLog("[Daymark][BENCH] sync keystroke: median %.3f ms  p95 %.3f ms  (%d lines)", sync.median, sync.p95, cachedTokens.lines.count)

        let a = NSRange(location: insertLoc, length: 0)
        let b = NSRange(location: line.location + line.length + 1, length: 0)
        var reconcileTimes: [Double] = []
        for i in 0..<300 {
            textView.setSelectedRange(i % 2 == 0 ? a : b)
            // setSelectedRange fires the delegate reconcile synchronously and advances the
            // baseline, so force a real diff here to measure the per-caret-move cost.
            lastConcealmentSelection = i % 2 == 0 ? b : a
            let t = CFAbsoluteTimeGetCurrent()
            reconcileConcealment()
            reconcileTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        let reconcile = stats(reconcileTimes)
        NSLog("[Daymark][BENCH] reconcileConcealment: median %.3f ms  p95 %.3f ms", reconcile.median, reconcile.p95)

        if let cardController {
            var repoTimes: [Double] = []
            for _ in 0..<100 {
                let t = CFAbsoluteTimeGetCurrent()
                cardController.repositionCards()
                repoTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            }
            let repo = stats(repoTimes)
            NSLog("[Daymark][BENCH] repositionCards: median %.3f ms  p95 %.3f ms", repo.median, repo.p95)
        }
        NSLog("[Daymark][BENCH] done")
    }
    #endif
}
