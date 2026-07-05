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
        // cache, none of that happened, so the whole-document re-apply (measured at ~260ms on a
        // 5k-line note, dominated by the emphasis pass) is pure waste and reflows nothing new.
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

    /// Restyles exactly the paragraph a checkbox toggle changed, and nothing else. A toggle is
    /// a bounded, same-length `[ ]`/`[x]` edit that cannot open or close a fence and cannot
    /// start or end a generated region (the toggler refuses lines inside a region), so there is
    /// no need for the whole-document `styleAll()` a normal edit schedules. Skipping it removes
    /// the debounced full-document `setAttributes` + card reposition that reflows the note under
    /// the toggled line, which is the relayout that glitched the following checkbox (Bug 1). It
    /// also targets the toggled line directly instead of the caret's line, since a click toggle
    /// leaves the caret where it was.
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
        // Built in ascending order directly (prefix slice, then the rescanned paragraph, then the
        // shifted tail), so no sort is needed. Split points come from a binary search over the
        // sorted cache, and the prefix is a bulk slice copy rather than a filtered scan of the
        // whole array; only the tail is walked, and only to shift it. The prior `append + sort`
        // was O(n log n) per keystroke over the whole cache; on a 5k-line note that was the bulk
        // of the sync path.
        let cachedLines = cachedTokens.lines
        let linePrefixEnd = Self.lowerBound(cachedLines, location: editedRange.location) { $0.range.location }
        var lineSuffixStart = linePrefixEnd
        while lineSuffixStart < cachedLines.count, cachedLines[lineSuffixStart].range.location <= editedRange.location {
            lineSuffixStart += 1
        }

        // The edited paragraph previously ran up to the next cached line's start (or the document
        // end when it was the last line). `NoteTokenScanner` records line ranges without the
        // trailing newline while `NSString.lineRange` includes it, so the delta must come from
        // these consistent line-start boundaries, never a line-length subtraction: that drifts by
        // one per edit (the newline) and used to be masked by the always-full debounced pass.
        let oldParagraphEnd = lineSuffixStart < cachedLines.count
            ? cachedLines[lineSuffixStart].range.location
            : editedRange.location + editedRange.length
        let delta = editedRange.location + editedRange.length - oldParagraphEnd

        var lines: [NoteTokens.Line] = []
        lines.reserveCapacity(cachedLines.count + tokens.lines.count)
        lines.append(contentsOf: cachedLines[..<linePrefixEnd])
        lines.append(contentsOf: tokens.lines)
        if delta == 0 {
            lines.append(contentsOf: cachedLines[lineSuffixStart...])
        } else {
            for i in lineSuffixStart..<cachedLines.count { lines.append(shifted(cachedLines[i], by: delta)) }
        }

        // Inline tokens inside the old paragraph are replaced by the rescan; everything at or past
        // the old paragraph end is shifted, not dropped.
        let cachedInline = cachedTokens.inlineTokens
        let inlinePrefixEnd = Self.lowerBound(cachedInline, location: editedRange.location) { $0.range.location }
        let inlineSuffixStart = Self.lowerBound(cachedInline, location: oldParagraphEnd) { $0.range.location }
        var inline: [NoteTokens.InlineToken] = []
        inline.reserveCapacity(cachedInline.count + tokens.inlineTokens.count)
        inline.append(contentsOf: cachedInline[..<inlinePrefixEnd])
        inline.append(contentsOf: tokens.inlineTokens)
        if delta == 0 {
            inline.append(contentsOf: cachedInline[inlineSuffixStart...])
        } else {
            for i in inlineSuffixStart..<cachedInline.count { inline.append(shifted(cachedInline[i], by: delta)) }
        }

        // Regions entirely after the edit shift by the same delta, so the cache keeps their
        // positions correct between debounced full passes (cards stay pinned while typing above
        // them) and, crucially, stays byte-equal to a fresh scan so `styleAll` can take its skip
        // path. A region that contains the edit is left as-is; its length changed, so the next
        // full scan will not match and will re-apply, which is the correct reconcile.
        let regions: [NoteTokens.GeneratedRegion]
        if delta == 0 {
            regions = cachedTokens.regions
        } else {
            regions = cachedTokens.regions.map { region in
                region.range.location >= oldParagraphEnd ? shifted(region, by: delta) : region
            }
        }
        cachedTokens = NoteTokens(lines: lines, inlineTokens: inline, regions: regions)

        // A non-fence-marker edit cannot open or close a fence (that path goes through
        // `styleAll()` above instead), so every recorded fence value stays correct; only the
        // locations after the edit need to move by the same delta the lines did.
        if delta != 0 {
            lineFenceStates = lineFenceStates.map { entry in
                entry.location > editedRange.location ? (entry.location + delta, entry.fence) : entry
            }

            // A fade in flight for a token must move with that token, or overlayAlpha and
            // stepRevealFades keep painting the pre-edit location after everything else has shifted.
            if !revealFades.isEmpty {
                var shiftedFades: [Int: RevealFade] = [:]
                shiftedFades.reserveCapacity(revealFades.count)
                for (key, fade) in revealFades {
                    if key < editedRange.location {
                        shiftedFades[key] = fade
                    } else if key < oldParagraphEnd {
                        continue
                    } else {
                        var shiftedFade = fade
                        shiftedFade.range = shifted(fade.range, by: delta)
                        shiftedFades[key + delta] = shiftedFade
                    }
                }
                revealFades = shiftedFades
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

    private func shifted(_ region: NoteTokens.GeneratedRegion, by delta: Int) -> NoteTokens.GeneratedRegion {
        NoteTokens.GeneratedRegion(
            hash: region.hash,
            range: shifted(region.range, by: delta),
            innerRange: shifted(region.innerRange, by: delta),
            commandLineRange: region.commandLineRange.map { shifted($0, by: delta) }
        )
    }

    private func shifted(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    /// First index in a location-sorted array whose element location is >= `location`.
    private static func lowerBound<T>(_ items: [T], location: Int, _ key: (T) -> Int) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if key(items[mid]) < location { low = mid + 1 } else { high = mid }
        }
        return low
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
        // `addAttribute` ran its own storage fixups and layout notification, which on a full-
        // document pass was the bulk of the restyle cost (measured at ~230ms on a 5k-line note,
        // ~7ms batched).
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
