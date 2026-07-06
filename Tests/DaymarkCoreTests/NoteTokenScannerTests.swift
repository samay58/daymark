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
        let tokens = NoteTokenScanner.scanLines(markdown, in: secondLineRange)
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
        let tokens = NoteTokenScanner.scanLines(markdown, in: lineRange)

        XCTAssertEqual(tokens.lines.count, 1)
        XCTAssertEqual(tokens.lines[0].kind, .fence)
        XCTAssertTrue(tokens.inlineTokens.isEmpty)
    }

    func testScanLinesRangeStartingInsideFenceSuppressesTagAndDue() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let dueLocation = nsLocation(of: "x due:2026-07-08", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: dueLocation, length: 0))
        let tokens = NoteTokenScanner.scanLines(markdown, in: lineRange)
        XCTAssertEqual(tokens.lines[0].kind, .fence)
        XCTAssertTrue(tokens.inlineTokens.filter { if case .dueDate = $0.kind { return true } else { return false } }.isEmpty)

        guard let tagLocation = nsLocation(of: "#tag-inside-fence", in: ns) else { return }
        let tagLineRange = ns.lineRange(for: NSRange(location: tagLocation, length: 0))
        let tagTokens = NoteTokenScanner.scanLines(markdown, in: tagLineRange)
        XCTAssertEqual(tagTokens.lines[0].kind, .fence)
        XCTAssertTrue(tagTokens.inlineTokens.filter { $0.kind == .tag }.isEmpty)
    }

    func testScanLinesRangeAfterFenceClassifiesNormally() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let afterLocation = nsLocation(of: "- [ ] after the fence due:2026-07-09", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: afterLocation, length: 0))
        let tokens = NoteTokenScanner.scanLines(markdown, in: lineRange)
        guard case .task = tokens.lines[0].kind else {
            return XCTFail("expected task after the fence, got \(tokens.lines[0].kind)")
        }
        XCTAssertTrue(tokens.inlineTokens.contains { if case .dueDate = $0.kind { return true } else { return false } })
    }

    func testScanLinesFenceOverloadWithSuppliedStateMatchesWalk() {
        let markdown = Self.fenceHeavyDocument
        let ns = markdown as NSString
        guard let sampleLocation = nsLocation(of: "- [ ] sample", in: ns) else { return }
        let lineRange = ns.lineRange(for: NSRange(location: sampleLocation, length: 0))

        // Build the fence state a caller would maintain by consuming every prior trimmed line.
        var fence = MarkdownFenceScanner()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: lineRange.location), options: .byLines) { substring, _, _, _ in
            _ = fence.consume(trimmedLine: (substring ?? "").trimmingCharacters(in: .whitespaces))
        }

        let walked = NoteTokenScanner.scanLines(markdown, in: lineRange)
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
            let incremental = NoteTokenScanner.scanLines(markdown, in: NSRange(location: start, length: 0))
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
        let incremental = NoteTokenScanner.scanLines(markdown, in: NSRange(location: insideLocation, length: 0))
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
