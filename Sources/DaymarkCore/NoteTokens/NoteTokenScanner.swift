import Foundation

public enum NoteTokenScanner {
    public static func scan(_ text: String) -> NoteTokens {
        scanFull(text)
    }

    /// Scans only the requested line range, but stays fence-aware: fence state is derived by
    /// walking every line from the document start up to the range, doing only trimmed-prefix
    /// fence consumption (no classification, no inline scanning), so lines inside an open fence
    /// classify as `.fence` exactly like `scan(_:)` would. Existing callers keep this signature
    /// and keep getting correct output; callers that already track fence state (for example a
    /// cache built from a prior full scan) should use the overload below to skip the walk.
    public static func scanLines(_ text: String, in lineRange: NSRange) -> NoteTokens {
        let nsText = text as NSString
        let expanded = expandedLineRange(for: lineRange, in: nsText)
        let fence = fenceState(upTo: expanded.location, in: nsText)
        return scanLinesCore(nsText: nsText, expanded: expanded, fence: fence)
    }

    /// Same as `scanLines(_:in:)`, but takes caller-maintained fence state at the start of
    /// `lineRange` instead of walking the document from the start to derive it. The caller is
    /// responsible for keeping `fence` in sync with the document (for example by updating it
    /// alongside a cached full scan). This does not change or replace the walking overload above.
    public static func scanLines(_ text: String, in lineRange: NSRange, fence: MarkdownFenceScanner) -> NoteTokens {
        let nsText = text as NSString
        let expanded = expandedLineRange(for: lineRange, in: nsText)
        return scanLinesCore(nsText: nsText, expanded: expanded, fence: fence)
    }

    private static func expandedLineRange(for lineRange: NSRange, in nsText: NSString) -> NSRange {
        let clampedLocation = min(max(0, lineRange.location), nsText.length)
        let clamped = NSRange(
            location: clampedLocation,
            length: max(0, min(lineRange.length, nsText.length - clampedLocation))
        )
        return nsText.lineRange(for: clamped)
    }

    /// Walks every line from the document start up to (but excluding) `location`, feeding only
    /// the trimmed line prefix to the fence scanner. No classification or token scanning happens
    /// here; this exists purely to reconstruct fence state cheaply for a mid-document range.
    private static func fenceState(upTo location: Int, in nsText: NSString) -> MarkdownFenceScanner {
        var fence = MarkdownFenceScanner()
        guard location > 0 else { return fence }
        let priorRange = NSRange(location: 0, length: location)
        nsText.enumerateSubstrings(in: priorRange, options: .byLines) { substring, _, _, _ in
            let content = substring ?? ""
            let leadingCount = leadingWhitespaceCount(content)
            let leftTrimmed = String(content.dropFirst(leadingCount))
            _ = fence.consume(trimmedLine: leftTrimmed)
        }
        return fence
    }

    private static func scanLinesCore(
        nsText: NSString,
        expanded: NSRange,
        fence: MarkdownFenceScanner
    ) -> NoteTokens {
        var fence = fence
        let source = nsText as String
        var lines: [NoteTokens.Line] = []
        var inlineTokens: [NoteTokens.InlineToken] = []
        nsText.enumerateSubstrings(in: expanded, options: .byLines) { substring, substringRange, _, _ in
            let content = substring ?? ""
            let leadingCount = leadingWhitespaceCount(content)
            let markerStart = substringRange.location + leadingCount
            let leftTrimmed = String(content.dropFirst(leadingCount))
            let lineEnd = substringRange.location + substringRange.length

            let wasDelimiter = fence.consume(trimmedLine: leftTrimmed)
            if wasDelimiter || fence.isInsideFence {
                lines.append(NoteTokens.Line(range: substringRange, kind: .fence))
                return
            }

            let kind = classify(leftTrimmed: leftTrimmed, markerStart: markerStart, lineEnd: lineEnd)
            lines.append(NoteTokens.Line(range: substringRange, kind: kind))
            inlineTokens.append(contentsOf: lineInlineTokens(
                for: kind,
                text: source,
                nsText: nsText,
                rawRange: substringRange,
                markerStart: markerStart,
                lineEnd: lineEnd
            ))
            inlineTokens.append(contentsOf: machineTextTokens(text: source, nsText: nsText, rawRange: substringRange))
        }
        return NoteTokens(lines: lines, inlineTokens: inlineTokens, regions: [])
    }

    private static func scanFull(_ text: String) -> NoteTokens {
        let nsText = text as NSString
        let source = nsText as String
        var rawLines: [(range: NSRange, content: String)] = []
        let fullRange = NSRange(location: 0, length: nsText.length)
        nsText.enumerateSubstrings(in: fullRange, options: .byLines) { substring, substringRange, _, _ in
            rawLines.append((substringRange, substring ?? ""))
        }

        var lines: [NoteTokens.Line] = []
        var inlineTokens: [NoteTokens.InlineToken] = []
        var fence = MarkdownFenceScanner()

        for raw in rawLines {
            let leadingCount = leadingWhitespaceCount(raw.content)
            let markerStart = raw.range.location + leadingCount
            let leftTrimmed = String(raw.content.dropFirst(leadingCount))

            let wasDelimiter = fence.consume(trimmedLine: leftTrimmed)
            if wasDelimiter || fence.isInsideFence {
                lines.append(NoteTokens.Line(range: raw.range, kind: .fence))
                continue
            }

            let lineEnd = raw.range.location + raw.range.length
            let kind = classify(
                leftTrimmed: leftTrimmed,
                markerStart: markerStart,
                lineEnd: lineEnd
            )
            lines.append(NoteTokens.Line(range: raw.range, kind: kind))
            inlineTokens.append(contentsOf: lineInlineTokens(
                for: kind,
                text: source,
                nsText: nsText,
                rawRange: raw.range,
                markerStart: markerStart,
                lineEnd: lineEnd
            ))
            inlineTokens.append(contentsOf: machineTextTokens(text: source, nsText: nsText, rawRange: raw.range))
        }

        let regions = scanRegions(nsText: nsText, rawLines: rawLines, lines: lines)

        return NoteTokens(lines: lines, inlineTokens: inlineTokens, regions: regions)
    }

    private static func leadingWhitespaceCount(_ content: String) -> Int {
        var count = 0
        for character in content {
            if character == " " || character == "\t" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func classify(leftTrimmed: String, markerStart: Int, lineEnd: Int) -> NoteTokens.LineKind {
        if leftTrimmed.isEmpty {
            return .blank
        }
        if let heading = headingMarker(leftTrimmed, markerStart: markerStart) {
            return heading
        }
        if let task = taskLine(leftTrimmed, markerStart: markerStart, lineEnd: lineEnd) {
            return task
        }
        if let bullet = bulletMarker(leftTrimmed, markerStart: markerStart) {
            return bullet
        }
        if leftTrimmed.hasPrefix(">") {
            return .quote
        }
        if let command = commandLine(leftTrimmed) {
            return command
        }
        return .body
    }

    private static func headingMarker(_ trimmed: String, markerStart: Int) -> NoteTokens.LineKind? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let markerRange = NSRange(location: markerStart, length: hashes.count)
        return .heading(level: hashes.count, markerRange: markerRange)
    }

    private static func taskLine(_ trimmed: String, markerStart: Int, lineEnd: Int) -> NoteTokens.LineKind? {
        guard trimmed.hasPrefix("- ["), trimmed.count >= 5 else { return nil }
        let chars = Array(trimmed)
        guard chars[4] == "]" else { return nil }
        let done: Bool
        switch chars[3] {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }

        let markerRange = NSRange(location: markerStart, length: 2)
        let boxRange = NSRange(location: markerStart + 2, length: 3)
        var textStart = markerStart + 5
        if textStart <= lineEnd, textStart < markerStart + trimmed.utf16.count, isSpace(trimmed, at: 5) {
            textStart += 1
        }
        let textLength = max(0, lineEnd - textStart)
        let textRange = NSRange(location: textStart, length: textLength)
        return .task(done: done, markerRange: markerRange, boxRange: boxRange, textRange: textRange)
    }

    private static func isSpace(_ trimmed: String, at utf16Offset: Int) -> Bool {
        let utf16 = trimmed.utf16
        guard utf16Offset < utf16.count else { return false }
        let index = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
        return utf16[index] == 0x20
    }

    private static func bulletMarker(_ trimmed: String, markerStart: Int) -> NoteTokens.LineKind? {
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return .bullet(markerRange: NSRange(location: markerStart, length: 2))
            }
        }
        return nil
    }

    private static func commandLine(_ trimmed: String) -> NoteTokens.LineKind? {
        let parts = trimmed.split { $0 == " " || $0 == "\t" }.map(String.init)
        guard parts.first == "/daymark", parts.count >= 2 else { return nil }
        guard DynamicBlockCommand(rawValue: parts[1]) != nil else { return nil }
        return .commandLine(command: parts[1])
    }

    // MARK: - Inline tokens

    private static let tagRegex = try! NSRegularExpression(pattern: "#[\\p{L}\\p{N}_/-]+")
    private static let wikilinkRegex = try! NSRegularExpression(pattern: "\\[\\[[^\\[\\]\\r\\n]+\\]\\]")
    private static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+")
    private static let dueRegex = try! NSRegularExpression(pattern: "due:\\S+")
    private static let rolloverMarkerRegex = try! NSRegularExpression(pattern: "<!--[ \\t]*daymark-rollover:[^\\r\\n]*?-->")
    private static let provenanceRegex = try! NSRegularExpression(pattern: "\\(from [^)\\r\\n]+:[0-9]+\\)")

    /// Machine text a rolled-over line carries that must never render raw: the
    /// `<!-- daymark-rollover:<hash> -->` dedup marker and the `(from <path>:<line>)`
    /// provenance parenthetical. Detection is gated on the marker's presence so ordinary
    /// prose like "(from the archive)" is never picked up. Ranges are UTF-16 (NSRange), so
    /// emoji earlier on the line shift them correctly and TextKit conceals the right glyphs.
    /// Callers only invoke this for non-fence lines, so fenced sample markdown stays literal.
    private static func machineTextTokens(text: String, nsText: NSString, rawRange: NSRange) -> [NoteTokens.InlineToken] {
        guard rawRange.length > 0, rawRange.location >= 0, rawRange.location + rawRange.length <= nsText.length else { return [] }
        guard contains(nsText, "daymark-rollover:", in: rawRange) else { return [] }
        var tokens: [NoteTokens.InlineToken] = []
        rolloverMarkerRegex.enumerateMatches(in: text, options: [], range: rawRange) { match, _, _ in
            guard let match else { return }
            tokens.append(NoteTokens.InlineToken(range: match.range, kind: .rolloverMarker))
        }
        provenanceRegex.enumerateMatches(in: text, options: [], range: rawRange) { match, _, _ in
            guard let match else { return }
            tokens.append(NoteTokens.InlineToken(range: match.range, kind: .provenance))
        }
        return tokens
    }

    private static func lineInlineTokens(
        for kind: NoteTokens.LineKind,
        text: String,
        nsText: NSString,
        rawRange: NSRange,
        markerStart: Int,
        lineEnd: Int
    ) -> [NoteTokens.InlineToken] {
        switch kind {
        case .heading(_, let markerRange):
            let titleStart = markerRange.location + markerRange.length + 1
            guard titleStart <= lineEnd else { return [] }
            let titleRange = NSRange(location: titleStart, length: lineEnd - titleStart)
            return scanInline(text: text, nsText: nsText, range: titleRange, includeDue: false)
        case .task(_, _, _, let textRange):
            return scanInline(text: text, nsText: nsText, range: textRange, includeDue: true)
        case .bullet(let markerRange):
            let start = markerRange.location + markerRange.length
            guard start <= lineEnd else { return [] }
            let bulletRange = NSRange(location: start, length: lineEnd - start)
            return scanInline(text: text, nsText: nsText, range: bulletRange, includeDue: false)
        case .quote:
            var start = markerStart + 1
            if start <= lineEnd, nsText.length > start, nsText.character(at: start) == 0x20 {
                start += 1
            }
            guard start <= lineEnd else { return [] }
            let quoteRange = NSRange(location: start, length: lineEnd - start)
            return scanInline(text: text, nsText: nsText, range: quoteRange, includeDue: false)
        case .body:
            return scanInline(text: text, nsText: nsText, range: rawRange, includeDue: false)
        case .commandLine, .fence, .blank:
            return []
        }
    }

    private static func scanInline(text: String, nsText: NSString, range: NSRange, includeDue: Bool) -> [NoteTokens.InlineToken] {
        guard range.length > 0, range.location >= 0, range.location + range.length <= nsText.length else { return [] }
        var tokens: [NoteTokens.InlineToken] = []

        if contains(nsText, "#", in: range) {
            tagRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                tokens.append(NoteTokens.InlineToken(range: match.range, kind: .tag))
            }
        }
        if contains(nsText, "[[", in: range) {
            wikilinkRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                tokens.append(NoteTokens.InlineToken(range: match.range, kind: .wikilink))
            }
        }
        if contains(nsText, "http", in: range) {
            urlRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                tokens.append(NoteTokens.InlineToken(range: match.range, kind: .url))
            }
        }
        if includeDue, contains(nsText, "due:", in: range) {
            dueRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                let tokenText = nsText.substring(with: match.range)
                let value = String(tokenText.dropFirst("due:".count))
                guard let display = cachedDueDisplay(for: value) else { return }
                tokens.append(NoteTokens.InlineToken(range: match.range, kind: .dueDate(display: display)))
            }
        }

        return tokens
    }

    private static let dueCacheLock = NSLock()
    nonisolated(unsafe) private static var dueDisplayCache: [String: String?] = [:]

    private static func cachedDueDisplay(for value: String) -> String? {
        dueCacheLock.lock()
        if let cached = dueDisplayCache[value] {
            dueCacheLock.unlock()
            return cached
        }
        dueCacheLock.unlock()

        let computed = TaskItem.Due(token: value)?.displayText()
        dueCacheLock.lock()
        dueDisplayCache[value] = computed
        dueCacheLock.unlock()
        return computed
    }

    private static func contains(_ nsText: NSString, _ needle: String, in range: NSRange) -> Bool {
        nsText.range(of: needle, options: [], range: range).location != NSNotFound
    }

    // MARK: - Regions

    private static func scanRegions(
        nsText: NSString,
        rawLines: [(range: NSRange, content: String)],
        lines: [NoteTokens.Line]
    ) -> [NoteTokens.GeneratedRegion] {
        let lineContents = rawLines.map(\.content)
        var regions: [NoteTokens.GeneratedRegion] = []
        var index = 0

        while index < lineContents.count {
            if let hash = GeneratedRegionMarker.beginHash(in: lineContents[index]),
               let endIndex = GeneratedRegionMarker.endIndex(afterBegin: index, hash: hash, in: lineContents) {
                let beginLineRange = rawLines[index].range
                let endLineRange = rawLines[endIndex].range
                let fullRange = NSRange(
                    location: beginLineRange.location,
                    length: (endLineRange.location + endLineRange.length) - beginLineRange.location
                )
                let innerRange: NSRange
                if endIndex > index + 1 {
                    let innerStart = rawLines[index + 1].range
                    let innerEnd = rawLines[endIndex - 1].range
                    innerRange = NSRange(
                        location: innerStart.location,
                        length: (innerEnd.location + innerEnd.length) - innerStart.location
                    )
                } else {
                    innerRange = NSRange(location: beginLineRange.location + beginLineRange.length, length: 0)
                }

                var commandLineRange: NSRange?
                if index > 0, case .commandLine = lines[index - 1].kind {
                    commandLineRange = lines[index - 1].range
                }

                regions.append(NoteTokens.GeneratedRegion(
                    hash: hash,
                    range: fullRange,
                    innerRange: innerRange,
                    commandLineRange: commandLineRange
                ))
                index = endIndex + 1
                continue
            }
            index += 1
        }

        return regions
    }
}
