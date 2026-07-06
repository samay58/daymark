import Foundation

public enum NoteTokenCacheReducer {
    public struct LineFenceState: Sendable {
        public let location: Int
        public let fence: MarkdownFenceScanner

        public init(location: Int, fence: MarkdownFenceScanner) {
            self.location = location
            self.fence = fence
        }
    }

    public struct KeyedRange: Sendable, Equatable {
        public let key: Int
        public let range: NSRange

        public init(key: Int, range: NSRange) {
            self.key = key
            self.range = range
        }
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
        public let oldParagraphEnd: Int
        public let delta: Int

        public init(state: State, oldParagraphEnd: Int, delta: Int) {
            self.state = state
            self.oldParagraphEnd = oldParagraphEnd
            self.delta = delta
        }
    }

    public static func merge(state: State, rescanned tokens: NoteTokens, editedRange: NSRange) -> Result {
        let cachedLines = state.tokens.lines
        let linePrefixEnd = lowerBound(cachedLines, location: editedRange.location) { $0.range.location }
        var lineSuffixStart = linePrefixEnd
        while lineSuffixStart < cachedLines.count, cachedLines[lineSuffixStart].range.location <= editedRange.location {
            lineSuffixStart += 1
        }

        let oldParagraphEnd = lineSuffixStart < cachedLines.count
            ? cachedLines[lineSuffixStart].range.location
            : editedRange.location + editedRange.length
        let delta = editedRange.location + editedRange.length - oldParagraphEnd

        var lines: [NoteTokens.Line] = []
        lines.reserveCapacity(cachedLines.count + tokens.lines.count)
        lines.append(contentsOf: cachedLines[..<linePrefixEnd])
        lines.append(contentsOf: tokens.lines)
        appendShiftedLines(cachedLines, from: lineSuffixStart, delta: delta, into: &lines)

        let cachedInline = state.tokens.inlineTokens
        let inlinePrefixEnd = lowerBound(cachedInline, location: editedRange.location) { $0.range.location }
        let inlineSuffixStart = lowerBound(cachedInline, location: oldParagraphEnd) { $0.range.location }
        var inline: [NoteTokens.InlineToken] = []
        inline.reserveCapacity(cachedInline.count + tokens.inlineTokens.count)
        inline.append(contentsOf: cachedInline[..<inlinePrefixEnd])
        inline.append(contentsOf: tokens.inlineTokens)
        appendShiftedInlineTokens(cachedInline, from: inlineSuffixStart, delta: delta, into: &inline)

        let regions = state.tokens.regions.map { region in
            region.range.location >= oldParagraphEnd ? shifted(region, by: delta) : region
        }
        let fenceStates = state.lineFenceStates.map { entry in
            entry.location > editedRange.location
                ? LineFenceState(location: entry.location + delta, fence: entry.fence)
                : entry
        }

        return Result(
            state: State(
                tokens: NoteTokens(lines: lines, inlineTokens: inline, regions: regions),
                lineFenceStates: fenceStates
            ),
            oldParagraphEnd: oldParagraphEnd,
            delta: delta
        )
    }

    public static func shiftKeyedRanges(
        _ ranges: [KeyedRange],
        editStart: Int,
        oldParagraphEnd: Int,
        delta: Int
    ) -> [KeyedRange] {
        ranges.compactMap { item in
            if item.key < editStart { return item }
            if item.key < oldParagraphEnd { return nil }
            return KeyedRange(key: item.key + delta, range: shifted(item.range, by: delta))
        }
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

    public static func canMergeIncrementally(text: String, editedRange: NSRange) -> Bool {
        let nsText = text as NSString
        let clamped = clampedRange(editedRange, length: nsText.length)
        let lineRange = nsText.lineRange(for: clamped)
        var canMerge = true
        nsText.enumerateSubstrings(in: lineRange, options: .byLines) { substring, _, _, stop in
            guard let first = leftTrimmed(substring ?? "").first else { return }
            if first == "`" || first == "~" {
                canMerge = false
                stop.pointee = true
            }
        }
        return canMerge
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

    private static func clampedRange(_ range: NSRange, length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}
