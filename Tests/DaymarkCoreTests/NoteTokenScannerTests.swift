import XCTest
@testable import DaymarkCore

final class NoteTokenScannerTests: XCTestCase {
    private func line(_ tokens: NoteTokens, _ index: Int) -> NoteTokens.Line {
        tokens.lines[index]
    }

    // MARK: - Headings

    func testHeadingLevelsAndMarkerRanges() {
        let markdown = "# One\n## Two\n### Three"
        let tokens = NoteTokenScanner.scan(markdown)

        guard case .heading(let level0, let marker0) = line(tokens, 0).kind else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level0, 1)
        XCTAssertEqual(marker0, NSRange(location: 0, length: 1))

        guard case .heading(let level1, let marker1) = line(tokens, 1).kind else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level1, 2)
        XCTAssertEqual(marker1.length, 2)

        guard case .heading(let level2, _) = line(tokens, 2).kind else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level2, 3)
    }

    // MARK: - Tasks

    func testOpenTask() {
        let markdown = "- [ ] wash the car"
        let tokens = NoteTokenScanner.scan(markdown)
        guard case .task(let done, let markerRange, let boxRange, let textRange) = line(tokens, 0).kind else {
            return XCTFail("expected task")
        }
        XCTAssertFalse(done)
        XCTAssertEqual(markerRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(boxRange, NSRange(location: 2, length: 3))
        XCTAssertEqual((markdown as NSString).substring(with: textRange), "wash the car")
    }

    func testDoneTask() {
        let markdown = "- [x] wash the car"
        let tokens = NoteTokenScanner.scan(markdown)
        guard case .task(let done, _, let boxRange, _) = line(tokens, 0).kind else {
            return XCTFail("expected task")
        }
        XCTAssertTrue(done)
        XCTAssertEqual((markdown as NSString).substring(with: boxRange), "[x]")
    }

    func testNestedIndentedTask() {
        let markdown = "  - [ ] indented task"
        let tokens = NoteTokenScanner.scan(markdown)
        guard case .task(_, let markerRange, _, let textRange) = line(tokens, 0).kind else {
            return XCTFail("expected task")
        }
        XCTAssertEqual(markerRange.location, 2)
        XCTAssertEqual((markdown as NSString).substring(with: textRange), "indented task")
    }

    // MARK: - Inline tokens

    func testTagToken() {
        let markdown = "- [ ] ping Sarah #launch about the demo"
        let tokens = NoteTokenScanner.scan(markdown)
        let tagTokens = tokens.inlineTokens.filter { $0.kind == .tag }
        XCTAssertEqual(tagTokens.count, 1)
        XCTAssertEqual((markdown as NSString).substring(with: tagTokens[0].range), "#launch")
    }

    func testWikilinkToken() {
        let markdown = "See [[Project Notes]] for details"
        let tokens = NoteTokenScanner.scan(markdown)
        let wikilinkTokens = tokens.inlineTokens.filter { $0.kind == .wikilink }
        XCTAssertEqual(wikilinkTokens.count, 1)
        XCTAssertEqual((markdown as NSString).substring(with: wikilinkTokens[0].range), "[[Project Notes]]")
    }

    func testURLToken() {
        let markdown = "Read https://example.com/docs for reference"
        let tokens = NoteTokenScanner.scan(markdown)
        let urlTokens = tokens.inlineTokens.filter { $0.kind == .url }
        XCTAssertEqual(urlTokens.count, 1)
        XCTAssertEqual((markdown as NSString).substring(with: urlTokens[0].range), "https://example.com/docs")
    }

    func testDueTodayToken() {
        let markdown = "- [ ] call the vet due:today"
        let tokens = NoteTokenScanner.scan(markdown)
        let dueTokens = tokens.inlineTokens.compactMap { token -> String? in
            if case .dueDate(let display) = token.kind { return display }
            return nil
        }
        XCTAssertEqual(dueTokens, ["Today"])
    }

    func testDueTomorrowToken() {
        let markdown = "- [ ] call the vet due:tomorrow"
        let tokens = NoteTokenScanner.scan(markdown)
        let dueTokens = tokens.inlineTokens.compactMap { token -> String? in
            if case .dueDate(let display) = token.kind { return display }
            return nil
        }
        XCTAssertEqual(dueTokens, ["Tomorrow"])
    }

    func testDueISODateTokenHumanizes() {
        let markdown = "- [ ] call the vet due:2026-07-08"
        let tokens = NoteTokenScanner.scan(markdown)
        let dueTokens = tokens.inlineTokens.compactMap { token -> String? in
            if case .dueDate(let display) = token.kind { return display }
            return nil
        }
        XCTAssertEqual(dueTokens, ["Jul 8"])
    }

    func testInvalidDueTokenIsNotTokenized() {
        let markdown = "- [ ] call the vet due:whenever"
        let tokens = NoteTokenScanner.scan(markdown)
        let dueTokens = tokens.inlineTokens.filter { if case .dueDate = $0.kind { return true } else { return false } }
        XCTAssertTrue(dueTokens.isEmpty)
    }

    // MARK: - Command lines

    func testKnownCommandLines() {
        let commands = ["open-loops", "source-list", "codex-context", "weekly-review"]
        for command in commands {
            let markdown = "/daymark \(command)"
            let tokens = NoteTokenScanner.scan(markdown)
            guard case .commandLine(let parsedCommand) = line(tokens, 0).kind else {
                XCTFail("expected commandLine for \(command)")
                continue
            }
            XCTAssertEqual(parsedCommand, command)
        }
    }

    func testUnknownCommandLineIsBody() {
        let markdown = "/daymark not-a-real-command"
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(line(tokens, 0).kind, .body)
    }

    // MARK: - Fences

    func testFenceExcludesAllTokenTypes() {
        let markdown = """
        - [ ] real task

        ```
        # heading inside fence
        - [ ] sample inside the fence
        #tag-inside-fence
        ```

        - [ ] another real task
        """
        let tokens = NoteTokenScanner.scan(markdown)

        let fenceLines = tokens.lines.filter { $0.kind == .fence }
        XCTAssertEqual(fenceLines.count, 5)

        XCTAssertTrue(tokens.inlineTokens.allSatisfy { token in
            !fenceLines.contains { NSIntersectionRange($0.range, token.range).length > 0 }
        })

        let taskLines = tokens.lines.filter { if case .task = $0.kind { return true } else { return false } }
        XCTAssertEqual(taskLines.count, 2)
    }

    func testFenceRespectsFenceTypeAndLength() {
        let markdown = """
        - [ ] real task

        ```
        ~~~
        - [ ] sample inside the fence
        - [x] also inside the fence
        ```

        - [ ] another real task
        """
        let tokens = NoteTokenScanner.scan(markdown)
        let taskLines = tokens.lines.filter { if case .task = $0.kind { return true } else { return false } }
        XCTAssertEqual(taskLines.count, 2)
    }

    // MARK: - Regions

    func testWellFormedRegion() {
        let markdown = """
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        ### Open Loops

        No open loops.
        <!-- daymark:block-end abc123 -->
        """
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(tokens.regions.count, 1)
        let region = tokens.regions[0]
        XCTAssertEqual(region.hash, "abc123")
        XCTAssertNotNil(region.commandLineRange)
        XCTAssertEqual((markdown as NSString).substring(with: region.commandLineRange!), "/daymark open-loops")

        let innerText = (markdown as NSString).substring(with: region.innerRange)
        XCTAssertTrue(innerText.contains("Open Loops"))
        XCTAssertFalse(innerText.contains("block-begin"))
        XCTAssertFalse(innerText.contains("block-end"))

        let fullText = (markdown as NSString).substring(with: region.range)
        XCTAssertTrue(fullText.hasPrefix("<!-- daymark:block-begin abc123 -->"))
        XCTAssertTrue(fullText.hasSuffix("<!-- daymark:block-end abc123 -->"))
    }

    func testUnpairedBeginMarkerYieldsNoRegion() {
        let markdown = """
        <!-- daymark:block-begin abc123 -->
        ### Open Loops
        No open loops.
        """
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertTrue(tokens.regions.isEmpty)
    }

    func testHashMismatchedPairYieldsNoRegion() {
        let markdown = """
        <!-- daymark:block-begin abc123 -->
        ### Open Loops
        <!-- daymark:block-end zzz999 -->
        """
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertTrue(tokens.regions.isEmpty)
    }

    func testAdjacentRegions() {
        let markdown = """
        <!-- daymark:block-begin aaa111 -->
        first
        <!-- daymark:block-end aaa111 -->
        <!-- daymark:block-begin bbb222 -->
        second
        <!-- daymark:block-end bbb222 -->
        """
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(tokens.regions.count, 2)
        XCTAssertEqual(tokens.regions[0].hash, "aaa111")
        XCTAssertEqual(tokens.regions[1].hash, "bbb222")
    }

    func testRegionAtDocumentStartAndEnd() {
        let markdown = "<!-- daymark:block-begin xyz789 -->\nbody\n<!-- daymark:block-end xyz789 -->"
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(tokens.regions.count, 1)
        XCTAssertEqual(tokens.regions[0].range.location, 0)
        let region = tokens.regions[0]
        XCTAssertEqual(region.range.location + region.range.length, (markdown as NSString).length)
        XCTAssertNil(region.commandLineRange)
    }

    // MARK: - CRLF

    func testCRLFDocumentRangesAccountForCR() {
        let markdown = "- [ ] first\r\n- [x] second\r\n"
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(tokens.lines.count, 2)

        guard case .task(_, _, _, let textRange0) = line(tokens, 0).kind else {
            return XCTFail("expected task")
        }
        XCTAssertEqual((markdown as NSString).substring(with: textRange0), "first")

        guard case .task(let done1, _, _, let textRange1) = line(tokens, 1).kind else {
            return XCTFail("expected task")
        }
        XCTAssertTrue(done1)
        XCTAssertEqual((markdown as NSString).substring(with: textRange1), "second")

        // Line ranges must exclude the trailing CR/LF terminator.
        let nsMarkdown = markdown as NSString
        XCTAssertFalse(nsMarkdown.substring(with: line(tokens, 0).range).contains("\r"))
    }

    // MARK: - Emoji

    func testEmojiBeforeCheckboxKeepsUTF16Ranges() {
        let markdown = "🔥 - [ ] flagged task"
        let tokens = NoteTokenScanner.scan(markdown)
        // The line starts with a non-whitespace emoji, so the whole line is body, not a task,
        // matching TaskParser's own "- [" prefix requirement after trimming whitespace only.
        XCTAssertEqual(line(tokens, 0).kind, .body)

        let markdownIndented = "- [ ] 🔥 flagged task"
        let indentedTokens = NoteTokenScanner.scan(markdownIndented)
        guard case .task(_, _, _, let textRange) = line(indentedTokens, 0).kind else {
            return XCTFail("expected task")
        }
        XCTAssertEqual((markdownIndented as NSString).substring(with: textRange), "🔥 flagged task")
    }

    // MARK: - Empty string

    func testEmptyStringProducesNoLines() {
        let tokens = NoteTokenScanner.scan("")
        XCTAssertTrue(tokens.lines.isEmpty)
        XCTAssertTrue(tokens.inlineTokens.isEmpty)
        XCTAssertTrue(tokens.regions.isEmpty)
    }

    // MARK: - Blank lines

    func testBlankLine() {
        let markdown = "text\n\nmore text"
        let tokens = NoteTokenScanner.scan(markdown)
        XCTAssertEqual(line(tokens, 1).kind, .blank)
    }

    // MARK: - scanLines (incremental)

    func testScanLinesReturnsRequestedLine() {
        let markdown = "# Heading\n- [ ] task one\n- [x] task two"
        let nsMarkdown = markdown as NSString
        let secondLineRange = nsMarkdown.lineRange(for: NSRange(location: nsMarkdown.length - 5, length: 0))
        let tokens = scanLinesWithCachedFence(markdown, in: secondLineRange)
        XCTAssertTrue(tokens.lines.contains { if case .task = $0.kind { return true } else { return false } })
    }

    // MARK: - scanLines fence awareness

    private static let fenceHeavyDocument = """
    - [ ] before the fence due:2026-07-08
    #before-tag

    ```
    - [ ] sample
    #tag-inside-fence
    x due:2026-07-08
    ```

    - [ ] after the fence due:2026-07-09
    #after-tag
    """

    private func nsLocation(of needle: String, in ns: NSString, file: StaticString = #filePath, line: UInt = #line) -> Int? {
        let found = ns.range(of: needle, options: [])
        guard found.location != NSNotFound else {
            XCTFail("fixture missing expected line: \(needle)", file: file, line: line)
            return nil
        }
        return found.location
    }

    func testScanLinesRangeStartingInsideFenceClassifiesFence() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        // "- [ ] sample" is the first line inside the fence.
        guard let sampleLocation = nsLocation(of: "- [ ] sample", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: sampleLocation, length: 0))
        let tokens = scanLinesWithCachedFence(markdown, in: lineRange)

        XCTAssertEqual(tokens.lines.count, 1)
        XCTAssertEqual(tokens.lines[0].kind, .fence)
        XCTAssertTrue(tokens.inlineTokens.isEmpty)
    }

    func testScanLinesRangeStartingInsideFenceSuppressesTagAndDue() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let dueLocation = nsLocation(of: "x due:2026-07-08", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: dueLocation, length: 0))
        let tokens = scanLinesWithCachedFence(markdown, in: lineRange)
        XCTAssertEqual(tokens.lines[0].kind, .fence)
        XCTAssertTrue(tokens.inlineTokens.filter { if case .dueDate = $0.kind { return true } else { return false } }.isEmpty)

        guard let tagLocation = nsLocation(of: "#tag-inside-fence", in: ns) else { return }
        let tagLineRange = ns.lineRange(for: NSRange(location: tagLocation, length: 0))
        let tagTokens = scanLinesWithCachedFence(markdown, in: tagLineRange)
        XCTAssertEqual(tagTokens.lines[0].kind, .fence)
        XCTAssertTrue(tagTokens.inlineTokens.filter { $0.kind == .tag }.isEmpty)
    }

    func testScanLinesRangeAfterFenceClassifiesNormally() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let afterLocation = nsLocation(of: "- [ ] after the fence due:2026-07-09", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: afterLocation, length: 0))
        let tokens = scanLinesWithCachedFence(markdown, in: lineRange)
        guard case .task = tokens.lines[0].kind else {
            return XCTFail("expected task after the fence, got \(tokens.lines[0].kind)")
        }
        XCTAssertTrue(tokens.inlineTokens.contains { if case .dueDate = $0.kind { return true } else { return false } })
    }

    func testCachedFenceStateMatchesManualWalk() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let sampleLocation = nsLocation(of: "- [ ] sample", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: sampleLocation, length: 0))

        // Build the fence state a caller would maintain by consuming every prior trimmed line.
        var fence = MarkdownFenceScanner()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: lineRange.location), options: .byLines) { substring, _, _, _ in
            _ = fence.consume(trimmedLine: (substring ?? "").trimmingCharacters(in: .whitespaces))
        }

        let walked = scanLinesWithCachedFence(markdown, in: lineRange)
        let supplied = NoteTokenScanner.scanLines(markdown, in: lineRange, fence: fence)
        XCTAssertEqual(walked, supplied)
    }

    func testScanFullAndScanLinesParityAcrossFenceHeavyDocument() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        let full = NoteTokenScanner.scan(markdown)

        var lineStarts: [Int] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { _, range, _, _ in
            lineStarts.append(range.location)
        }

        for start in lineStarts {
            // Request via a zero-length range at the line start, same as callers (caret/click)
            // do; `incremental.lines.first?.range` is the actual scanned line (terminator
            // excluded, matching how `scan(_:)` records line ranges).
            let incremental = scanLinesWithCachedFence(markdown, in: NSRange(location: start, length: 0))
            guard let scannedRange = incremental.lines.first?.range else {
                XCTFail("scanLines produced no line at \(start)")
                continue
            }
            guard let fullLine = full.lines.first(where: { $0.range == scannedRange }) else {
                XCTFail("no full-scan line for range \(scannedRange)")
                continue
            }
            XCTAssertEqual(incremental.lines.first?.kind, fullLine.kind, "mismatch at \(scannedRange)")

            let fullInlineInRange = full.inlineTokens.filter { NSIntersectionRange($0.range, scannedRange).length > 0 }
            XCTAssertEqual(Set(incremental.inlineTokens.map(\.range)), Set(fullInlineInRange.map(\.range)), "inline mismatch at \(scannedRange)")
        }
    }

    func testCRLFFenceParity() {
        let markdown = "- [ ] before\r\n```\r\n- [ ] inside\r\n```\r\n- [ ] after\r\n"
        let ns = markdown as NSString
        let full = NoteTokenScanner.scan(markdown)

        guard let insideLocation = nsLocation(of: "- [ ] inside", in: ns) else { return }
        let incremental = scanLinesWithCachedFence(markdown, in: NSRange(location: insideLocation, length: 0))
        XCTAssertEqual(incremental.lines[0].kind, .fence)
        guard let scannedRange = incremental.lines.first?.range else {
            return XCTFail("scanLines produced no line")
        }
        XCTAssertFalse(ns.substring(with: scannedRange).contains("\r"), "line range should exclude CRLF terminator")

        guard let fullLine = full.lines.first(where: { $0.range == scannedRange }) else {
            return XCTFail("no full-scan line for range \(scannedRange)")
        }
        XCTAssertEqual(fullLine.kind, .fence)
    }
}

// MARK: - Differential safety net: full scan versus line-by-line scan

/// Generates a deterministic (fixed-seed) corpus of synthetic notes and checks that `scan(_:)`
/// matches the concatenation of `scanLines(_:in:fence:)` walked line by line with independently
/// tracked fence state, mirroring how the live editor scans. The two paths share one per-line
/// classifier, and this guards against either growing a rule the other lacks.
final class NoteTokenScannerCorpusTests: XCTestCase {
    /// Splitmix64, chosen only for being a small, dependency-free, reproducible generator;
    /// no cryptographic property is needed here.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static func randomCorpus(count: Int, seed: UInt64) -> [String] {
        var rng = SeededGenerator(seed: seed)
        return (0..<count).map { _ in randomNote(&rng) }
    }

    private static func randomNote(_ rng: inout SeededGenerator) -> String {
        let lineCount = Int.random(in: 4...24, using: &rng)
        var lines: [String] = []
        var openFence: Character?

        for _ in 0..<lineCount {
            if let fenceChar = openFence {
                if Double.random(in: 0...1, using: &rng) < 0.3 {
                    lines.append(String(repeating: fenceChar, count: 3))
                    openFence = nil
                } else {
                    lines.append(randomFenceBody(&rng))
                }
                continue
            }
            lines.append(randomLine(&rng, openingFence: &openFence))
        }
        if openFence != nil {
            lines.append(String(repeating: openFence!, count: 3))
        }

        let useCRLF = Bool.random(using: &rng)
        return lines.joined(separator: useCRLF ? "\r\n" : "\n")
    }

    private static func randomFenceBody(_ rng: inout SeededGenerator) -> String {
        let bodies = [
            "# heading that must stay literal",
            "- [ ] task that must stay literal",
            "#tag-that-must-stay-literal",
            "[[Link that must stay literal]]",
            "https://example.com/inside-fence",
            "plain text inside the fence",
            ""
        ]
        return bodies[Int.random(in: 0..<bodies.count, using: &rng)]
    }

    private static func randomLine(_ rng: inout SeededGenerator, openingFence: inout Character?) -> String {
        let emojiPool = ["", "🔥 ", "✅ ", "📌 "]
        let emoji = emojiPool[Int.random(in: 0..<emojiPool.count, using: &rng)]
        let index = Int.random(in: 0..<100_000, using: &rng)

        switch Int.random(in: 0..<16, using: &rng) {
        case 0:
            let level = Int.random(in: 1...7, using: &rng)
            return "\(String(repeating: "#", count: level)) \(emoji)Heading \(index) #tag\(index)"
        case 1:
            return "- [ ] \(emoji)follow up on \(index) due:2026-\(pad(Int.random(in: 1...12, using: &rng)))-\(pad(Int.random(in: 1...28, using: &rng)))"
        case 2:
            return "- [x] \(emoji)done with \(index) #done"
        case 3:
            return "- \(emoji)bullet item \(index) [[Note \(index)]]"
        case 4:
            return "* \(emoji)star bullet \(index) https://example.com/\(index)"
        case 5:
            return "+ \(emoji)plus bullet \(index)"
        case 6:
            return "> \(emoji)quoted line \(index) #quoted"
        case 7:
            return ""
        case 8:
            let commands = ["open-loops", "source-list", "codex-context", "weekly-review", "not-a-real-command"]
            return "/daymark \(commands[Int.random(in: 0..<commands.count, using: &rng)])"
        case 9:
            openingFence = Bool.random(using: &rng) ? "`" : "~"
            return String(repeating: openingFence!, count: 3)
        case 10:
            let hash = String(format: "%06x", index)
            return "<!-- daymark:block-begin \(hash) -->"
        case 11:
            let hash = String(format: "%06x", index)
            return "<!-- daymark:block-end \(hash) -->"
        case 12:
            let hash = String(format: "%08x", index)
            return "- \(emoji)rolled: follow up (from daily/2026/06/2026-06-2\(index % 8).md:\(index % 40)) <!-- daymark-rollover:\(hash) -->"
        case 13:
            return "\(emoji)plain prose about \(index) with due:whenever and due:2026-13-40 that should not tokenize"
        case 14:
            return "  - [ ] \(emoji)indented task \(index) #nested/tag"
        default:
            return "\(emoji)See [[Ref \(index)]] and https://example.com/\(index)/path also #tag\(index)/child due:\(index % 2 == 0 ? "today" : "tomorrow")"
        }
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private func leftTrimmed(_ content: String) -> String {
        var result = Substring(content)
        while let first = result.first, first == " " || first == "\t" {
            result = result.dropFirst()
        }
        return String(result)
    }

    /// Reconstructs a full scan by walking the document one line at a time through
    /// `scanLines(_:in:fence:)`, independently tracking fence state the same way the live
    /// editor's cache does. A full scan and this walk must always agree.
    private func chunkedScan(_ text: String) -> (lines: [NoteTokens.Line], inline: [NoteTokens.InlineToken]) {
        let ns = text as NSString
        guard ns.length > 0 else { return ([], []) }

        var fence = MarkdownFenceScanner()
        var lines: [NoteTokens.Line] = []
        var inline: [NoteTokens.InlineToken] = []
        var location = 0

        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let chunk = NoteTokenScanner.scanLines(text, in: lineRange, fence: fence)
            lines.append(contentsOf: chunk.lines)
            inline.append(contentsOf: chunk.inlineTokens)

            // Fence consumption needs terminator-free content; reuse the range the scanner
            // itself already computed rather than re-deriving terminator stripping here.
            if let contentRange = chunk.lines.first?.range {
                let content = ns.substring(with: contentRange)
                _ = fence.consume(trimmedLine: leftTrimmed(content))
            }
            location = lineRange.location + lineRange.length
        }
        return (lines, inline)
    }

    func testScanLinesChunkedWalkMatchesFullScanAcrossRandomCorpus() {
        let corpus = Self.randomCorpus(count: 320, seed: 0xC0FFEE)
        for (index, note) in corpus.enumerated() {
            let full = NoteTokenScanner.scan(note)
            let chunked = chunkedScan(note)
            XCTAssertEqual(chunked.lines, full.lines, "line mismatch at corpus index \(index)")
            XCTAssertEqual(chunked.inline, full.inlineTokens, "inline token mismatch at corpus index \(index)")
        }
    }
}
