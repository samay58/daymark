import Foundation
import DaymarkCore

public struct SourceSelection: Equatable, Sendable {
    public var excerpt: String
    public var sourcePath: String
    public var startLine: Int?
    public var endLine: Int?
    public var heading: String?

    public init(
        excerpt: String,
        sourcePath: String,
        startLine: Int?,
        endLine: Int?,
        heading: String?
    ) {
        self.excerpt = excerpt
        self.sourcePath = sourcePath
        self.startLine = startLine
        self.endLine = endLine
        self.heading = heading
    }
}

public struct SourceSelector {
    public enum Error: Swift.Error, Equatable {
        case emptySource
    }

    public init() {}

    public func select(
        text: String,
        selectedRange: NSRange,
        cursorLocation: Int,
        sourcePath: String
    ) throws -> SourceSelection {
        let normalized = normalize(text)
        let normalizedCursor = normalizeLocation(cursorLocation, in: text)
        let lines = lineRecords(for: normalized)

        if selectedRange.length > 0 {
            let selected = (text as NSString).substring(with: selectedRange)
            let excerpt = trimBlankLines(normalize(selected))
            guard !excerpt.isEmpty else { throw Error.emptySource }
            let start = lineNumber(at: normalizeLocation(selectedRange.location, in: text), lines: lines)
            let endLocation = normalizeLocation(selectedRange.location + selectedRange.length, in: text)
            let end = lineNumber(at: max(0, endLocation - 1), lines: lines)
            return SourceSelection(
                excerpt: excerpt,
                sourcePath: sourcePath,
                startLine: start,
                endLine: end,
                heading: heading(beforeOrAt: start, lines: lines)
            )
        }

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.emptySource
        }

        let index = blockLineIndex(near: normalizedCursor, lines: lines)
        guard let range = blockRange(containing: index, lines: lines), !range.isEmpty else {
            throw Error.emptySource
        }
        let excerpt = trimBlankLines(lines[range].map(\.text).joined(separator: "\n"))
        guard !excerpt.isEmpty else { throw Error.emptySource }

        let startLine = lines[range.lowerBound].number
        let endLine = lines[range.upperBound - 1].number
        return SourceSelection(
            excerpt: excerpt,
            sourcePath: sourcePath,
            startLine: startLine,
            endLine: endLine,
            heading: heading(beforeOrAt: startLine, lines: lines)
        )
    }

    private struct LineRecord {
        let number: Int
        let text: String
        let start: Int
        let end: Int
    }

    private func normalize(_ text: String) -> String {
        text.normalizedNewlines
    }

    private func normalizeLocation(_ location: Int, in original: String) -> Int {
        let clamped = max(0, min(location, (original as NSString).length))
        let prefix = (original as NSString).substring(with: NSRange(location: 0, length: clamped))
        return (normalize(prefix) as NSString).length
    }

    private func lineRecords(for text: String) -> [LineRecord] {
        let parts = text.components(separatedBy: "\n")
        var start = 0
        return parts.enumerated().map { offset, line in
            let end = start + (line as NSString).length
            defer { start = end + 1 }
            return LineRecord(number: offset + 1, text: line, start: start, end: end)
        }
    }

    private func blockLineIndex(near location: Int, lines: [LineRecord]) -> Int {
        guard !lines.isEmpty else { return 0 }
        let current = lines.firstIndex { location >= $0.start && location <= $0.end } ?? (lines.count - 1)
        if !lines[current].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return current
        }
        if let next = lines[current...].firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return next
        }
        if let previous = lines[..<current].lastIndex(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return previous
        }
        return current
    }

    private func blockRange(containing index: Int, lines: [LineRecord]) -> Range<Int>? {
        if let fence = fencedRange(containing: index, lines: lines) {
            return fence
        }
        if isListLike(lines[index].text) || isIndentedContinuation(lines[index].text) {
            return listRange(containing: index, lines: lines)
        }
        if isHeading(lines[index].text) {
            return firstContentRange(afterHeadingAt: index, lines: lines)
        }
        return paragraphRange(containing: index, lines: lines)
    }

    private func fencedRange(containing index: Int, lines: [LineRecord]) -> Range<Int>? {
        var scanner = MarkdownFenceScanner()
        var fenceStart: Int?
        for offset in lines.indices {
            let trimmed = lines[offset].text.trimmingCharacters(in: .whitespaces)
            let wasInside = scanner.isInsideFence
            guard scanner.consume(trimmedLine: trimmed) else { continue }
            if !wasInside {
                fenceStart = offset
            } else if let start = fenceStart {
                if index >= start, index <= offset {
                    return start..<(offset + 1)
                }
                fenceStart = nil
            }
        }
        return nil
    }

    private func listRange(containing index: Int, lines: [LineRecord]) -> Range<Int> {
        var start = index
        while start > 0, isIndentedContinuation(lines[start].text) {
            start -= 1
        }

        var end = start + 1
        while end < lines.count {
            let line = lines[end].text
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isListLike(line) || isHeading(line) {
                break
            }
            guard isIndentedContinuation(line) else { break }
            end += 1
        }
        return start..<end
    }

    private func paragraphRange(containing index: Int, lines: [LineRecord]) -> Range<Int> {
        var start = index
        while start > 0, isParagraphLine(lines[start - 1].text) {
            start -= 1
        }

        var end = index + 1
        while end < lines.count, isParagraphLine(lines[end].text) {
            end += 1
        }
        return start..<end
    }

    private func firstContentRange(afterHeadingAt index: Int, lines: [LineRecord]) -> Range<Int>? {
        var contentIndex = index + 1
        while contentIndex < lines.count {
            if isHeading(lines[contentIndex].text) {
                return nil
            }
            if lines[contentIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentIndex += 1
                continue
            }
            if let fence = fencedRange(containing: contentIndex, lines: lines) {
                return fence
            }
            if isListLike(lines[contentIndex].text) || isIndentedContinuation(lines[contentIndex].text) {
                return listRange(containing: contentIndex, lines: lines)
            }
            return paragraphRange(containing: contentIndex, lines: lines)
        }
        return nil
    }

    private func heading(beforeOrAt lineNumber: Int?, lines: [LineRecord]) -> String? {
        guard let lineNumber else { return nil }
        var scanner = MarkdownFenceScanner()
        var heading: String?
        for line in lines where line.number <= lineNumber {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if scanner.consume(trimmedLine: trimmed) { continue }
            if scanner.isInsideFence { continue }
            guard isHeading(line.text) else { continue }
            heading = MarkdownHeading.strippingMarker(trimmed)
        }
        return heading
    }

    private func isParagraphLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isHeading(line) && !isListLike(line)
    }

    private func isHeading(_ line: String) -> Bool {
        MarkdownHeading.isHeading(line)
    }

    private func isListLike(_ line: String) -> Bool {
        line.range(of: #"^\s{0,3}([-*+]\s+|\d+\.\s+)"#, options: .regularExpression) != nil
    }

    private func isIndentedContinuation(_ line: String) -> Bool {
        line.range(of: #"^\s{2,}\S"#, options: .regularExpression) != nil
    }

    private func lineNumber(at location: Int, lines: [LineRecord]) -> Int? {
        lines.first { location >= $0.start && location <= $0.end }?.number
    }

    private func trimBlankLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
