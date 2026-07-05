import Foundation

public enum NoteTokenScanner {
    public static func scan(_ text: String) -> NoteTokens {
        scanFull(text)
    }

    public static func scanLines(_ text: String, in lineRange: NSRange) -> NoteTokens {
        let full = scanFull(text)
        let expanded = expandedLineRange(text, around: lineRange)
        let lines = full.lines.filter { NSIntersectionRange($0.range, expanded).length > 0 || $0.range.location == expanded.location + expanded.length }
        let inlineTokens = full.inlineTokens.filter { NSIntersectionRange($0.range, expanded).length > 0 }
        let regions = full.regions.filter { region in
            region.range.location >= expanded.location && region.range.location + region.range.length <= expanded.location + expanded.length
        }
        return NoteTokens(lines: lines, inlineTokens: inlineTokens, regions: regions)
    }

    private static func expandedLineRange(_ text: String, around range: NSRange) -> NSRange {
        let nsText = text as NSString
        return nsText.lineRange(for: range)
    }

    private static func scanFull(_ text: String) -> NoteTokens {
        let nsText = text as NSString
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

            switch kind {
            case .heading(_, let markerRange):
                let titleStart = markerRange.location + markerRange.length + 1
                if titleStart <= lineEnd {
                    let titleRange = NSRange(location: titleStart, length: lineEnd - titleStart)
                    inlineTokens.append(contentsOf: scanInline(in: nsText, range: titleRange, includeDue: false))
                }
            case .task(_, _, let boxRange, let textRange):
                _ = boxRange
                inlineTokens.append(contentsOf: scanInline(in: nsText, range: textRange, includeDue: true))
            case .bullet(let markerRange):
                let start = markerRange.location + markerRange.length
                if start <= lineEnd {
                    let bulletRange = NSRange(location: start, length: lineEnd - start)
                    inlineTokens.append(contentsOf: scanInline(in: nsText, range: bulletRange, includeDue: false))
                }
            case .quote:
                var start = markerStart + 1
                if start <= lineEnd, nsText.length > start, nsText.character(at: start) == 0x20 {
                    start += 1
                }
                if start <= lineEnd {
                    let quoteRange = NSRange(location: start, length: lineEnd - start)
                    inlineTokens.append(contentsOf: scanInline(in: nsText, range: quoteRange, includeDue: false))
                }
            case .body:
                inlineTokens.append(contentsOf: scanInline(in: nsText, range: raw.range, includeDue: false))
            case .commandLine, .fence, .blank:
                break
            }
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

    private static func scanInline(in nsText: NSString, range: NSRange, includeDue: Bool) -> [NoteTokens.InlineToken] {
        guard range.length > 0, range.location >= 0, range.location + range.length <= nsText.length else { return [] }
        var tokens: [NoteTokens.InlineToken] = []

        tagRegex.enumerateMatches(in: nsText as String, options: [], range: range) { match, _, _ in
            guard let match else { return }
            tokens.append(NoteTokens.InlineToken(range: match.range, kind: .tag))
        }
        wikilinkRegex.enumerateMatches(in: nsText as String, options: [], range: range) { match, _, _ in
            guard let match else { return }
            tokens.append(NoteTokens.InlineToken(range: match.range, kind: .wikilink))
        }
        urlRegex.enumerateMatches(in: nsText as String, options: [], range: range) { match, _, _ in
            guard let match else { return }
            tokens.append(NoteTokens.InlineToken(range: match.range, kind: .url))
        }
        if includeDue {
            dueRegex.enumerateMatches(in: nsText as String, options: [], range: range) { match, _, _ in
                guard let match else { return }
                let tokenText = nsText.substring(with: match.range)
                let value = String(tokenText.dropFirst("due:".count))
                guard let due = TaskItem.Due(token: value) else { return }
                tokens.append(NoteTokens.InlineToken(range: match.range, kind: .dueDate(display: humanize(due))))
            }
        }

        return tokens
    }

    private static func humanize(_ due: TaskItem.Due) -> String {
        switch due {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .date(let iso):
            let calendar = Calendar(identifier: .gregorian)
            guard let date = ISODate.date(from: iso, calendar: calendar) else { return iso }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
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
