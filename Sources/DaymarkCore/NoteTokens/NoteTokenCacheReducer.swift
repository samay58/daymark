import Foundation

/// Keeps a `NoteTokens` cache in step with an edited note without rescanning all of it. An edit
/// is widened to whole lines, those lines are rescanned, and every cached line, token, region,
/// and fence state after them shifts by the length change. When an edit could reclassify text
/// outside its own lines (a fence delimiter or a generated-region marker changed), `merge`
/// returns nil and the caller must rescan the whole note.
public enum NoteTokenCacheReducer {
    public struct LineFenceState: Sendable {
        public let location: Int
        public let fence: MarkdownFenceScanner

        public init(location: Int, fence: MarkdownFenceScanner) {
            self.location = location
            self.fence = fence
        }
    }

    /// One text replacement: `replacedRange`, in the text before the edit, was replaced by
    /// `insertedLength` UTF-16 units.
    public struct Edit: Sendable, Equatable {
        public let replacedRange: NSRange
        public let insertedLength: Int

        init(replacedRange: NSRange, insertedLength: Int) {
            self.replacedRange = replacedRange
            self.insertedLength = insertedLength
        }

        /// Builds an edit from what `NSTextStorage` reports after processing one: `editedRange`
        /// is in the text after the edit, and `changeInLength` is the net length change.
        public init(editedRange: NSRange, changeInLength: Int) {
            self.init(
                replacedRange: NSRange(location: editedRange.location, length: editedRange.length - changeInLength),
                insertedLength: editedRange.length
            )
        }

        public var delta: Int { insertedLength - replacedRange.length }

        /// The single edit equivalent to applying `self` and then `next`, where `next.replacedRange`
        /// is in the text `self` produced. The result can cover unchanged text between the two
        /// edits; that only widens what gets rescanned.
        public func followed(by next: Edit) -> Edit {
            let originalEnd = NSMaxRange(replacedRange)
            let currentEnd = replacedRange.location + insertedLength
            let start = min(replacedRange.location, next.replacedRange.location)
            let end = max(currentEnd, NSMaxRange(next.replacedRange))
            let replacedEnd = originalEnd + (end - currentEnd)
            return Edit(
                replacedRange: NSRange(location: start, length: replacedEnd - start),
                insertedLength: end + next.delta - start
            )
        }
    }

    /// The whole lines an edit touched. `oldRange` is in the text before the edit and `newRange`
    /// covers the replacement lines after it. Both start at the same location, and text after
    /// them is unchanged apart from shifting by `delta`.
    public struct Span: Sendable, Equatable {
        public let oldRange: NSRange
        public let newRange: NSRange

        public init(oldRange: NSRange, newRange: NSRange) {
            self.oldRange = oldRange
            self.newRange = newRange
        }

        public var delta: Int { newRange.length - oldRange.length }
    }

    public struct State: Sendable {
        public let tokens: NoteTokens
        public let lineFenceStates: [LineFenceState]

        public init(tokens: NoteTokens, lineFenceStates: [LineFenceState]) {
            self.tokens = tokens
            self.lineFenceStates = lineFenceStates
        }
    }

    public struct Result: Sendable {
        public let state: State
        public let span: Span
        /// The tokens for `span.newRange` alone, for callers that restyle just those lines.
        public let rescanned: NoteTokens

        public init(state: State, span: Span, rescanned: NoteTokens) {
            self.state = state
            self.span = span
            self.rescanned = rescanned
        }
    }

    /// The lines to rescan for `edit`, given `text` after the edit.
    private static func span(for edit: Edit, in text: String) -> Span {
        let nsText = text as NSString
        let length = nsText.length
        let editStart = min(max(0, edit.replacedRange.location), length)
        let editEnd = min(length, editStart + max(0, edit.insertedLength))
        // Reach one unit past the inserted text so the line holding the first unchanged
        // character is rescanned too; without it, an insertion that ends in a newline would
        // leave the tail of the old line unaccounted for. Reach one unit back after a bare CR,
        // because the edit may have split or joined a CRLF pair, which moves where the
        // previous line ends.
        var start = editStart
        if start > 0, nsText.character(at: start - 1) == 0x0D { start -= 1 }
        let end = min(length, editEnd + 1)
        let newRange = nsText.lineRange(for: NSRange(location: start, length: end - start))
        let oldRange = NSRange(location: newRange.location, length: newRange.length - edit.delta)
        return Span(oldRange: oldRange, newRange: newRange)
    }

    /// Applies `edit` to a cache that described the text before it. `text` is the text after the
    /// edit. Returns nil when the result could differ from a full `NoteTokenScanner.scan(text)`:
    /// a fence delimiter or region marker was added or removed, the edit touched a region's
    /// markers, or the cache does not line up with the edit.
    public static func merge(state: State, text: String, edit: Edit) -> Result? {
        let nsText = text as NSString
        let span = span(for: edit, in: text)
        guard span.oldRange.length >= 0 else { return nil }
        let oldStart = span.oldRange.location
        let oldEnd = NSMaxRange(span.oldRange)
        let delta = span.delta

        let cachedLines = state.tokens.lines
        let linePrefixEnd = lowerBound(cachedLines, location: oldStart) { $0.range.location }
        let lineSuffixStart = lowerBound(cachedLines, location: oldEnd) { $0.range.location }
        let fenceStates = state.lineFenceStates
        let fencePrefixEnd = lowerBound(fenceStates, location: oldStart) { $0.location }
        let fenceSuffixStart = lowerBound(fenceStates, location: oldEnd) { $0.location }
        guard startsAt(cachedLines, linePrefixEnd, oldStart, { $0.range.location }),
              startsAt(cachedLines, lineSuffixStart, oldEnd, { $0.range.location }),
              startsAt(fenceStates, fencePrefixEnd, oldStart, { $0.location }),
              fencePrefixEnd == linePrefixEnd,
              fenceSuffixStart == lineSuffixStart,
              let entering = fenceState(entering: fencePrefixEnd, states: fenceStates, lines: cachedLines, text: nsText)
        else { return nil }

        // A replaced line that toggled fence state was a delimiter; removing it reclassifies
        // everything after the span.
        for index in fencePrefixEnd..<fenceSuffixStart where index + 1 < fenceStates.count {
            if fenceStates[index].fence.isInsideFence != fenceStates[index + 1].fence.isInsideFence { return nil }
        }

        let rescanned = NoteTokenScanner.scanLines(text, in: span.newRange, fence: entering)
        for line in rescanned.lines {
            let content = nsText.substring(with: line.range)
            var probe = entering
            if probe.consume(trimmedLine: leftTrimmed(content)) { return nil }
            if GeneratedRegionMarker.beginHash(in: content) != nil || GeneratedRegionMarker.endHash(in: content) != nil {
                return nil
            }
        }

        guard let regions = mergedRegions(state.tokens.regions, cachedLines: cachedLines, span: span, rescanned: rescanned) else {
            return nil
        }

        var lines: [NoteTokens.Line] = []
        lines.reserveCapacity(cachedLines.count - (lineSuffixStart - linePrefixEnd) + rescanned.lines.count)
        lines.append(contentsOf: cachedLines[..<linePrefixEnd])
        lines.append(contentsOf: rescanned.lines)
        appendShiftedLines(cachedLines, from: lineSuffixStart, delta: delta, into: &lines)

        // Inline tokens are grouped by line, so a line boundary splits them with one binary search.
        let cachedInline = state.tokens.inlineTokens
        let inlinePrefixEnd = lowerBound(cachedInline, location: oldStart) { $0.range.location }
        let inlineSuffixStart = lowerBound(cachedInline, location: oldEnd) { $0.range.location }
        var inline: [NoteTokens.InlineToken] = []
        inline.reserveCapacity(cachedInline.count + rescanned.inlineTokens.count)
        inline.append(contentsOf: cachedInline[..<inlinePrefixEnd])
        inline.append(contentsOf: rescanned.inlineTokens)
        appendShiftedInlineTokens(cachedInline, from: inlineSuffixStart, delta: delta, into: &inline)

        // No rescanned line is a delimiter, so each one is entered with the same fence state.
        var mergedFenceStates: [LineFenceState] = []
        mergedFenceStates.reserveCapacity(lines.count)
        mergedFenceStates.append(contentsOf: fenceStates[..<fencePrefixEnd])
        for line in rescanned.lines {
            mergedFenceStates.append(LineFenceState(location: line.range.location, fence: entering))
        }
        for entry in fenceStates[fenceSuffixStart...] {
            mergedFenceStates.append(LineFenceState(location: entry.location + delta, fence: entry.fence))
        }

        return Result(
            state: State(
                tokens: NoteTokens(lines: lines, inlineTokens: inline, regions: regions),
                lineFenceStates: mergedFenceStates
            ),
            span: span,
            rescanned: rescanned
        )
    }

    /// Where `range`, a location in the text before the edit, lands after it. Nil when it started
    /// inside the replaced lines, whose tokens the rescan replaced.
    public static func shifted(_ range: NSRange, across span: Span) -> NSRange? {
        if range.location < span.oldRange.location { return range }
        if range.location < NSMaxRange(span.oldRange) { return nil }
        return shifted(range, by: span.delta)
    }

    public static func fenceStates(for text: String) -> [LineFenceState] {
        let nsText = text as NSString
        var result: [LineFenceState] = []
        var fence = MarkdownFenceScanner()
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byLines) { substring, range, _, _ in
            result.append(LineFenceState(location: range.location, fence: fence))
            _ = fence.consume(trimmedLine: leftTrimmed(substring ?? ""))
        }
        return result
    }

    /// Fence state entering the line at `index`. When the span starts at the end of the old
    /// text (appending after a trailing newline), no cached line starts there, so the state is
    /// derived by consuming the last cached line, which the edit did not change.
    private static func fenceState(
        entering index: Int,
        states: [LineFenceState],
        lines: [NoteTokens.Line],
        text: NSString
    ) -> MarkdownFenceScanner? {
        if index < states.count { return states[index].fence }
        guard let last = states.last, let lastLine = lines.last else { return MarkdownFenceScanner() }
        guard lastLine.range.location == last.location, NSMaxRange(lastLine.range) <= text.length else { return nil }
        var fence = last.fence
        _ = fence.consume(trimmedLine: leftTrimmed(text.substring(with: lastLine.range)))
        return fence
    }

    /// Regions before the span stay put and regions after it shift. A span inside a region's
    /// generated lines resizes that region. A span that ends on the line just above a begin
    /// marker can change whether that line is the region's command line. Any other overlap
    /// with a region returns nil.
    private static func mergedRegions(
        _ regions: [NoteTokens.GeneratedRegion],
        cachedLines: [NoteTokens.Line],
        span: Span,
        rescanned: NoteTokens
    ) -> [NoteTokens.GeneratedRegion]? {
        let oldStart = span.oldRange.location
        let oldEnd = NSMaxRange(span.oldRange)
        let delta = span.delta
        var result: [NoteTokens.GeneratedRegion] = []
        result.reserveCapacity(regions.count)

        for region in regions {
            let regionEnd = NSMaxRange(region.range)
            if regionEnd <= oldStart {
                result.append(region)
                continue
            }
            let beginIndex = lowerBound(cachedLines, location: region.range.location) { $0.range.location }
            guard beginIndex < cachedLines.count, cachedLines[beginIndex].range.location == region.range.location else { return nil }
            let lineAboveStart = beginIndex > 0 ? cachedLines[beginIndex - 1].range.location : region.range.location
            if lineAboveStart >= oldEnd {
                result.append(shifted(region, by: delta))
                continue
            }
            if oldEnd == region.range.location {
                guard let lineAbove = rescanned.lines.last else { return nil }
                let commandLineRange: NSRange?
                if case .commandLine = lineAbove.kind { commandLineRange = lineAbove.range } else { commandLineRange = nil }
                result.append(NoteTokens.GeneratedRegion(
                    hash: region.hash,
                    range: shifted(region.range, by: delta),
                    innerRange: shifted(region.innerRange, by: delta),
                    commandLineRange: commandLineRange
                ))
                continue
            }

            // An empty region's innerRange sits at the begin line's end rather than on a line
            // of its own, so this also rejects edits to regions with no generated lines.
            let beginLineEnd = NSMaxRange(cachedLines[beginIndex].range)
            let endIndex = lowerBound(cachedLines, location: regionEnd) { $0.range.location } - 1
            guard endIndex > beginIndex,
                  region.innerRange.location > beginLineEnd,
                  oldStart >= region.innerRange.location,
                  oldEnd <= cachedLines[endIndex].range.location,
                  let lastRescanned = rescanned.lines.last
            else { return nil }
            // When the span includes the last generated line, its terminator may have changed
            // length, so the new inner end comes from the rescan rather than from shifting.
            let innerEnd = oldEnd == cachedLines[endIndex].range.location
                ? NSMaxRange(lastRescanned.range)
                : NSMaxRange(region.innerRange) + delta
            result.append(NoteTokens.GeneratedRegion(
                hash: region.hash,
                range: NSRange(location: region.range.location, length: region.range.length + delta),
                innerRange: NSRange(location: region.innerRange.location, length: innerEnd - region.innerRange.location),
                commandLineRange: region.commandLineRange
            ))
        }
        return result
    }

    private static func appendShiftedLines(
        _ items: [NoteTokens.Line],
        from start: Int,
        delta: Int,
        into output: inout [NoteTokens.Line]
    ) {
        guard start < items.count else { return }
        if delta == 0 {
            output.append(contentsOf: items[start...])
        } else {
            for index in start..<items.count {
                output.append(shifted(items[index], by: delta))
            }
        }
    }

    private static func appendShiftedInlineTokens(
        _ items: [NoteTokens.InlineToken],
        from start: Int,
        delta: Int,
        into output: inout [NoteTokens.InlineToken]
    ) {
        guard start < items.count else { return }
        if delta == 0 {
            output.append(contentsOf: items[start...])
        } else {
            for index in start..<items.count {
                output.append(shifted(items[index], by: delta))
            }
        }
    }

    private static func shifted(_ line: NoteTokens.Line, by delta: Int) -> NoteTokens.Line {
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
        return NoteTokens.Line(range: shifted(line.range, by: delta), kind: newKind)
    }

    private static func shifted(_ token: NoteTokens.InlineToken, by delta: Int) -> NoteTokens.InlineToken {
        NoteTokens.InlineToken(range: shifted(token.range, by: delta), kind: token.kind)
    }

    private static func shifted(_ region: NoteTokens.GeneratedRegion, by delta: Int) -> NoteTokens.GeneratedRegion {
        NoteTokens.GeneratedRegion(
            hash: region.hash,
            range: shifted(region.range, by: delta),
            innerRange: shifted(region.innerRange, by: delta),
            commandLineRange: region.commandLineRange.map { shifted($0, by: delta) }
        )
    }

    private static func shifted(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    /// True when `index` is past the end or names an item that starts exactly at `location`,
    /// meaning `location` falls on a cached line boundary.
    private static func startsAt<T>(_ items: [T], _ index: Int, _ location: Int, _ key: (T) -> Int) -> Bool {
        index == items.count || key(items[index]) == location
    }

    private static func lowerBound<T>(_ items: [T], location: Int, _ key: (T) -> Int) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if key(items[mid]) < location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func leftTrimmed(_ content: String) -> String {
        var count = 0
        for character in content {
            if character == " " || character == "\t" { count += 1 } else { break }
        }
        return String(content.dropFirst(count))
    }
}
