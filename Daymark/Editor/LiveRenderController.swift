import AppKit
import DaymarkCore

@MainActor
final class LiveRenderController {
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
    /// Fence state entering each line, sorted by line start, so an edit can rescan its own lines
    /// without walking the note from the top to find out whether they sit inside a fence.
    private var lineFenceStates: [NoteTokenCacheReducer.LineFenceState] = []

    /// Character edits the text storage reported since `cachedTokens` last matched its text,
    /// folded into one replacement in the cached text's coordinates. Several storage edits can
    /// land before one `textDidChange` (undo groups, IME marked text), and the cache must be
    /// patched with all of them at once.
    private var pendingEdit: NoteTokenCacheReducer.Edit?
    private var storageEditObserver: StorageEditObserver?

    /// The selection the concealment attributes were last reconciled against. A caret move only
    /// flips the reveal state of tokens the caret entered or left, so `reconcileConcealment`
    /// diffs against this instead of rewriting concealment for every token on the note.
    /// Not private so the debug benchmark can force a real diff.
    var lastConcealmentSelection = NSRange(location: 0, length: 0)

    /// In-flight reveal crossfades, keyed by token start location. A caret entering or leaving a
    /// concealed checkbox, due pill, or machine-text run fades its literal text in or out and its
    /// drawn overlay out or in over `DesignMotion.revealFadeDuration` rather than snapping. Reduce Motion
    /// bypasses this and swaps instantly. An edit is authoritative and clears any fade for its range.
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
        storageEditObserver = textView.textStorage.map { storage in
            StorageEditObserver(storage: storage) { [weak self] edit in self?.recordEdit(edit) }
        }
    }

    static func baseFont() -> NSFont { .systemFont(ofSize: DesignType.bodySize) }

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

    /// Rescans the whole note and re-applies attributes when the scan differs from the cache.
    /// Pass `force` after the text was replaced wholesale (`textView.string = ...`): that gives
    /// the entire storage the first character's attributes, so a scan that happens to match the
    /// cache still needs every attribute re-applied.
    func styleAll(force: Bool = false) {
        guard let storage = textView?.textStorage else { return }
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let started = CFAbsoluteTimeGetCurrent()
        let tokens = NoteTokenScanner.scan(text)
        // A pending edit means the storage changed without an incremental restyle, so the
        // attributes around it were never applied even if the tokens came out the same.
        let storageChanged = pendingEdit != nil
        pendingEdit = nil

        // The debounced pass runs after every burst of typing. When the incremental path kept
        // the cache exact, the scan matches and a whole-document re-apply would only reflow.
        if !force, !storageChanged, tokens == cachedTokens {
            logFull(CFAbsoluteTimeGetCurrent() - started, lineCount: tokens.lines.count)
            return
        }

        if force { revealFades.removeAll() }
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

    /// Restyles the lines the pending edit touched and schedules the debounced full pass.
    func styleEditedParagraph() {
        guard restyleForPendingEdit() else { return }
        scheduleFullPass()
    }

    /// Restyles the line a checkbox toggle changed without scheduling the full pass. A toggle is
    /// a same-length `[ ]`/`[x]` replace that cannot move a fence or a region marker, so the
    /// whole-document pass would only reflow the note under the toggled line.
    func styleToggledLine() {
        _ = restyleForPendingEdit()
    }

    /// Returns false when there was nothing to restyle incrementally, either because no
    /// character edit is pending or because the edit forced a full pass instead.
    private func restyleForPendingEdit() -> Bool {
        guard let storage = textView?.textStorage else { return false }
        guard let edit = pendingEdit else {
            styleAll()
            return false
        }
        pendingEdit = nil
        let started = CFAbsoluteTimeGetCurrent()
        let text = storage.string
        let state = NoteTokenCacheReducer.State(tokens: cachedTokens, lineFenceStates: lineFenceStates)
        guard let result = NoteTokenCacheReducer.merge(state: state, text: text, edit: edit) else {
            // A fence delimiter or region marker moved, which can reclassify lines far from the
            // edit. Correct it now rather than after the debounce, so no stale decoration shows.
            styleAll(force: true)
            return false
        }
        cachedTokens = result.state.tokens
        lineFenceStates = result.state.lineFenceStates
        textVersion += 1
        shiftRevealFades(across: result.span)
        restyle(paragraph: result.span.newRange, tokens: result.rescanned)
        logSync(CFAbsoluteTimeGetCurrent() - started)
        return true
    }

    private func restyle(paragraph: NSRange, tokens: NoteTokens) {
        guard let textView, let storage = textView.textStorage else { return }
        apply(tokens, to: storage, in: paragraph)
        applyEmphasis(storage, tokens: tokens, in: paragraph)
        applyConcealment(tokens: tokens, selection: textView.selectedRange(), storage: storage)
        textView.needsDisplay = true
    }

    private func recordEdit(_ edit: NoteTokenCacheReducer.Edit) {
        pendingEdit = pendingEdit.map { $0.followed(by: edit) } ?? edit
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
            return 1 - EditorMotion.easeInOut(fade.progress)
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
            var previous: CFTimeInterval = 0
            await EditorMotion.runFrames { elapsed in
                guard let self, !self.revealFades.isEmpty else { return false }
                self.stepRevealFades(by: CGFloat((elapsed - previous) / DesignMotion.revealFadeDuration))
                previous = elapsed
                return !self.revealFades.isEmpty
            }
            self?.revealFadeTask = nil
        }
    }

    private func stepRevealFades(by step: CGFloat) {
        guard let textView, let storage = textView.textStorage else { revealFades.removeAll(); return }
        guard step > 0 else { return }
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
                storage.addAttribute(.foregroundColor, value: fade.revealedColor.withAlphaComponent(EditorMotion.easeInOut(fade.progress)), range: clamped)
                revealFades[key] = fade
            }
        }
        storage.endEditing()
        textView.needsDisplay = true
    }

    // MARK: - Cache maintenance

    /// Moves in-flight fades to their post-edit locations and drops the ones on replaced lines;
    /// the restyle that follows resolves those lines' concealment directly.
    private func shiftRevealFades(across span: NoteTokenCacheReducer.Span) {
        guard !revealFades.isEmpty else { return }
        var next: [Int: RevealFade] = [:]
        next.reserveCapacity(revealFades.count)
        for var fade in revealFades.values {
            guard let range = NoteTokenCacheReducer.shifted(fade.range, across: span) else { continue }
            fade.range = range
            next[range.location] = fade
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
        case .dueDate, .rolloverMarker, .provenance:
            // Concealable runs: `applyConcealment` owns their color (clear when hidden, revealed
            // color when the caret is inside), so there is nothing to add here.
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

    private static var traitCache: [FontTraitKey: NSFont] = [:]

    /// `NSFontManager.convert` is the dominant cost of the full-document emphasis pass (hundreds
    /// of ms on a 5k-line note when called once per bold/italic match). The set of distinct
    /// input fonts is tiny (body plus three heading weights), so memoize the conversions.
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
        .systemFont(ofSize: DesignType.headingSize(level: level), weight: .semibold)
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
}

/// Forwards character edits reported by a text storage. Observing the notification, rather
/// than taking the storage's delegate, leaves the delegate free for TextKit. Attribute-only
/// edits, which every styling pass makes, are ignored.
private final class StorageEditObserver {
    private let token: NSObjectProtocol

    @MainActor
    init(storage: NSTextStorage, onEdit: @escaping @MainActor (NoteTokenCacheReducer.Edit) -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { notification in
            guard let storage = notification.object as? NSTextStorage,
                  storage.editedMask.contains(.editedCharacters) else { return }
            let edit = NoteTokenCacheReducer.Edit(editedRange: storage.editedRange, changeInLength: storage.changeInLength)
            MainActor.assumeIsolated { onEdit(edit) }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
