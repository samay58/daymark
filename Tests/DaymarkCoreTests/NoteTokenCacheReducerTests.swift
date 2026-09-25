import XCTest
@testable import DaymarkCore

final class NoteTokenCacheReducerTests: XCTestCase {
    private typealias Reducer = NoteTokenCacheReducer

    private let threeTasks = "- [ ] one due:2026-07-01\n- [ ] two #tag\n- [ ] three [[Link]]\n"

    // MARK: - Line structure edits

    func testReturnAtEndOfLineAddsALine() {
        let at = (threeTasks as NSString).range(of: "\n").location
        let result = assertMerges(threeTasks, replacing: NSRange(location: at, length: 0), with: "\n")
        XCTAssertEqual(result?.state.tokens.lines.count, 4)
    }

    func testReturnMidLineSplitsTheLine() {
        let at = (threeTasks as NSString).range(of: "two").location + 1
        assertMerges(threeTasks, replacing: NSRange(location: at, length: 0), with: "\n")
    }

    func testBackspaceJoiningTwoLines() {
        let at = (threeTasks as NSString).range(of: "\n").location
        let result = assertMerges(threeTasks, replacing: NSRange(location: at, length: 1), with: "")
        XCTAssertEqual(result?.state.tokens.lines.count, 2)
        XCTAssertEqual(result?.span.delta, -1)
    }

    func testMultiLinePaste() {
        let at = (threeTasks as NSString).range(of: "two").location
        assertMerges(threeTasks, replacing: NSRange(location: at, length: 0), with: "pasted #x\n- [x] done due:2026-07-02\nmore [[A]] ")
    }

    func testDeletingAMultiLineSelection() {
        let ns = threeTasks as NSString
        let start = ns.range(of: "one").location
        let end = ns.range(of: "three").location
        assertMerges(threeTasks, replacing: NSRange(location: start, length: end - start), with: "")
    }

    func testTypingWithinALine() {
        let at = (threeTasks as NSString).range(of: "#tag").location
        let result = assertMerges(threeTasks, replacing: NSRange(location: at, length: 0), with: "x")
        XCTAssertEqual(result?.span.newRange, (applying(NSRange(location: at, length: 0), "x", to: threeTasks) as NSString).lineRange(for: NSRange(location: at, length: 0)))
    }

    func testEmojiInsertAndDelete() {
        let at = (threeTasks as NSString).range(of: "two").location
        assertMerges(threeTasks, replacing: NSRange(location: at, length: 0), with: "😀 ")
        let withEmoji = "- [ ] 😀 two #tag due:2026-07-01\n- [ ] after #b\n"
        let emoji = (withEmoji as NSString).range(of: "😀")
        XCTAssertEqual(emoji.length, 2)
        assertMerges(withEmoji, replacing: emoji, with: "")
    }

    func testCRLFText() {
        let crlf = "- [ ] one #a\r\n- [ ] two #b\r\n- [ ] three #c\r\n"
        let ns = crlf as NSString
        let firstBreak = ns.range(of: "\r\n").location
        // Return as CRLF, and a join that removes a whole CRLF.
        assertMerges(crlf, replacing: NSRange(location: firstBreak, length: 0), with: "\r\n")
        assertMerges(crlf, replacing: NSRange(location: firstBreak, length: 2), with: "")
        // Splitting and re-forming a CRLF pair moves the previous line's end.
        assertMerges(crlf, replacing: NSRange(location: firstBreak + 1, length: 1), with: "")
        assertMerges(crlf, replacing: NSRange(location: firstBreak + 1, length: 0), with: "x")
        let bareCR = "one #a\rtwo #b\r"
        assertMerges(bareCR, replacing: NSRange(location: 7, length: 0), with: "\n")
    }

    func testEmptyDocument() {
        assertMerges("", replacing: NSRange(location: 0, length: 0), with: "- [ ] first due:2026-07-01\n")
        assertMerges("- [ ] only #tag", replacing: NSRange(location: 0, length: 15), with: "")
    }

    func testEditAtDocumentEnd() {
        let noTrailingNewline = "alpha\n- [ ] beta"
        let end = (noTrailingNewline as NSString).length
        assertMerges(noTrailingNewline, replacing: NSRange(location: end, length: 0), with: " #tag")
        assertMerges(noTrailingNewline, replacing: NSRange(location: end, length: 0), with: "\n")
        assertMerges(noTrailingNewline, replacing: NSRange(location: end - 4, length: 4), with: "")
        let trailingNewline = "alpha\n- [ ] beta\n"
        let trailingEnd = (trailingNewline as NSString).length
        assertMerges(trailingNewline, replacing: NSRange(location: trailingEnd, length: 0), with: "- [ ] gamma")
        assertMerges(trailingNewline, replacing: NSRange(location: trailingEnd - 1, length: 1), with: "")
    }

    // MARK: - Generated regions

    private let regionNote = """
    intro #top
    /daymark open-loops
    <!-- daymark:block-begin abc123 -->
    - [ ] generated one
    - [ ] generated two
    <!-- daymark:block-end abc123 -->
    tail #end

    """

    func testEditAboveRegionShiftsRegionAndFenceState() {
        let result = assertMerges(regionNote, replacing: NSRange(location: 5, length: 0), with: " updated")
        XCTAssertEqual(result?.span.delta, " updated".utf16.count)
        XCTAssertEqual(result?.state.tokens.regions.count, 1)
    }

    func testReturnAboveRegionShiftsRegion() {
        assertMerges(regionNote, replacing: NSRange(location: 0, length: 0), with: "new line\n")
    }

    func testEditBelowRegionLeavesRegionAlone() {
        let at = (regionNote as NSString).range(of: "tail").location
        assertMerges(regionNote, replacing: NSRange(location: at, length: 0), with: "more\n")
    }

    func testEditInsideGeneratedLinesResizesRegion() {
        let ns = regionNote as NSString
        let one = ns.range(of: "generated one").location
        assertMerges(regionNote, replacing: NSRange(location: one, length: 0), with: "x")
        assertMerges(regionNote, replacing: NSRange(location: one, length: 0), with: "split\n")
        let two = ns.range(of: "generated two")
        assertMerges(regionNote, replacing: NSRange(location: NSMaxRange(two), length: 0), with: " #t")
    }

    func testEditingCommandLineUpdatesCommandLineRange() {
        let ns = regionNote as NSString
        let command = ns.range(of: "/daymark open-loops")
        let kept = assertMerges(regionNote, replacing: NSRange(location: NSMaxRange(command), length: 0), with: " #x")
        XCTAssertNotNil(kept?.state.tokens.regions.first?.commandLineRange)
        let broken = assertMerges(regionNote, replacing: NSRange(location: command.location, length: 1), with: "")
        XCTAssertNil(broken?.state.tokens.regions.first?.commandLineRange)
        // Return at the end of the command line puts a blank line between it and the region.
        let detached = assertMerges(regionNote, replacing: NSRange(location: NSMaxRange(command), length: 0), with: "\n")
        XCTAssertNil(detached?.state.tokens.regions.first?.commandLineRange)
    }

    func testEditingMarkerLinesRequiresFullPass() {
        let ns = regionNote as NSString
        let begin = ns.range(of: "<!-- daymark:block-begin")
        assertFallsBack(regionNote, replacing: NSRange(location: NSMaxRange(begin), length: 0), with: "x")
        let end = ns.range(of: "<!-- daymark:block-end")
        assertFallsBack(regionNote, replacing: NSRange(location: end.location, length: 0), with: "\n")
        let endLine = ns.lineRange(for: end)
        assertFallsBack(regionNote, replacing: endLine, with: "")
        // Typing a marker anywhere can pair with an existing orphan, so it rescans too.
        let tail = ns.range(of: "tail").location
        assertFallsBack(regionNote, replacing: NSRange(location: tail, length: 0), with: "<!-- daymark:block-end zzz -->\n")
    }

    // MARK: - Fences

    private let fenceNote = "before #a\n```\n- [ ] inside #not\n```\n- [ ] after #b\n"

    func testTypingInsideFenceMergesIncrementally() {
        let at = (fenceNote as NSString).range(of: "inside").location
        assertMerges(fenceNote, replacing: NSRange(location: at, length: 0), with: "x\n")
    }

    func testAddingOrRemovingAFenceDelimiterRequiresFullPass() {
        let ns = fenceNote as NSString
        assertFallsBack(fenceNote, replacing: NSRange(location: 0, length: 0), with: "```\n")
        let opener = ns.lineRange(for: ns.range(of: "```"))
        assertFallsBack(fenceNote, replacing: opener, with: "")
        // A backtick line that is not a delimiter changes nothing outside its own line.
        assertMerges(fenceNote, replacing: NSRange(location: 0, length: 0), with: "`code` ")
    }

    // MARK: - Edit composition and range shifting

    func testFollowedByMatchesApplyingBothEdits() {
        let base = "0123456789abcdef"
        let cases: [(NSRange, String, NSRange, String)] = [
            (NSRange(location: 10, length: 2), "XYZ", NSRange(location: 2, length: 1), ""),
            (NSRange(location: 2, length: 0), "ab", NSRange(location: 3, length: 4), "Q"),
            (NSRange(location: 5, length: 5), "", NSRange(location: 5, length: 0), "new"),
            (NSRange(location: 0, length: 3), "x", NSRange(location: 12, length: 1), "tail")
        ]
        for (firstRange, firstText, secondRange, secondText) in cases {
            let first = Reducer.Edit(replacedRange: firstRange, insertedLength: firstText.utf16.count)
            let second = Reducer.Edit(replacedRange: secondRange, insertedLength: secondText.utf16.count)
            let expected = applying(secondRange, secondText, to: applying(firstRange, firstText, to: base))
            let combined = first.followed(by: second)
            let inserted = (expected as NSString).substring(with: NSRange(location: combined.replacedRange.location, length: combined.insertedLength))
            XCTAssertEqual(applying(combined.replacedRange, inserted, to: base), expected)
        }
    }

    func testEditFromTextStorageReport() {
        let edit = Reducer.Edit(editedRange: NSRange(location: 4, length: 3), changeInLength: 2)
        XCTAssertEqual(edit.replacedRange, NSRange(location: 4, length: 1))
        XCTAssertEqual(edit.insertedLength, 3)
    }

    func testShiftedAcrossSpanDropsReplacedRangesAndMovesLaterOnes() {
        let span = Reducer.Span(oldRange: NSRange(location: 10, length: 20), newRange: NSRange(location: 10, length: 27))
        XCTAssertEqual(Reducer.shifted(NSRange(location: 5, length: 3), across: span), NSRange(location: 5, length: 3))
        XCTAssertNil(Reducer.shifted(NSRange(location: 20, length: 4), across: span))
        XCTAssertEqual(Reducer.shifted(NSRange(location: 40, length: 2), across: span), NSRange(location: 47, length: 2))
    }

    // MARK: - Differential

    /// Applies random edits to a realistic note, merging each into the running cache, and
    /// requires the merged cache to equal a fresh full scan whenever the reducer accepts it.
    /// Some iterations coalesce several edits first, the way several storage edits can land
    /// before one text-change notification.
    func testRandomEditsMatchFullScan() {
        var rng = SplitMix64(seed: 0xDA7_3A2C)
        var text = Self.realisticNote
        var state = fullState(text)
        let fragments = [
            "\n", "\n", "- [ ] ", "- [x] ", "#tag ", "due:2026-07-01", "😀", "🚀 ", "\r\n", "\r", "a", "word ",
            " ", "[[Link]]", "https://x.io ", "# ", "## ", "> ", "```", "~~~", "`code`", "* ", "\t",
            "<!-- daymark:block-begin abc123 -->", "<!-- daymark:block-end abc123 -->", "/daymark open-loops",
            "<!-- daymark-rollover:ff00 -->", "(from notes/a.md:3)"
        ]
        let iterations = 2_000
        var merged = 0
        var fellBack = 0

        for iteration in 0..<iterations {
            var edit: Reducer.Edit?
            let editCount = rng.next(upTo: 4) == 0 ? 2 + rng.next(upTo: 2) : 1
            for _ in 0..<editCount {
                let ns = text as NSString
                let length = ns.length
                let location = Self.safeBoundary(ns, rng.next(upTo: length + 1))
                let maxDelete = min(length - location, length > 3_000 ? 400 : 40)
                let deleteLength: Int
                switch rng.next(upTo: 3) {
                case 0: deleteLength = 0
                default: deleteLength = maxDelete > 0 ? rng.next(upTo: maxDelete + 1) : 0
                }
                let replaced = NSRange(location: location, length: Self.safeBoundary(ns, location + deleteLength) - location)
                var inserted = ""
                if rng.next(upTo: 4) != 0 || replaced.length == 0 {
                    for _ in 0..<(1 + rng.next(upTo: 3)) { inserted += fragments[rng.next(upTo: fragments.count)] }
                }
                text = applying(replaced, inserted, to: text)
                let step = Reducer.Edit(replacedRange: replaced, insertedLength: inserted.utf16.count)
                edit = edit.map { $0.followed(by: step) } ?? step
            }
            guard let edit else { continue }

            let fresh = NoteTokenScanner.scan(text)
            if let result = Reducer.merge(state: state, text: text, edit: edit) {
                merged += 1
                XCTAssertEqual(result.state.tokens, fresh, "iteration \(iteration)")
                assertFenceStatesMatch(result.state.lineFenceStates, text, "iteration \(iteration)")
                XCTAssertEqual(result.rescanned.lines, scanLinesWithCachedFence(text, in: result.span.newRange).lines, "iteration \(iteration)")
                if result.state.tokens != fresh { return }
                state = result.state
            } else {
                fellBack += 1
                state = fullState(text)
            }
        }

        XCTAssertEqual(merged + fellBack, iterations)
        // The test only proves something if most edits take the incremental path.
        XCTAssertGreaterThan(merged, iterations / 2, "merged \(merged), fell back \(fellBack)")
    }

    private static let realisticNote = """
    # Thursday, July 2

    ## Today's Brief
    - [ ] Ship the reducer fix due:2026-07-01 #daymark
    - [x] Review [[Design Review]] notes https://example.com/a
    - [ ] Call Sam 😀 about #plans/q3 due:tomorrow
      - nested bullet with **bold** and _italic_
    > a quote with #tag inside

    /daymark open-loops
    <!-- daymark:block-begin abc123 -->
    ### Open Loops
    - [ ] generated task  (notes/a.md:3)
    <!-- daymark:block-end abc123 -->

    ```swift
    - [ ] not a task #nottag
    ```
    - [ ] rolled task (from daily/2026-07-01.md:12) <!-- daymark-rollover:ab12 -->\r
    Body line with `code` and [[Another Link]]\r
    ~~~
    tilde fenced due:2026-07-03
    ~~~
    Last line 🚀 #end
    """

    // MARK: - Helpers

    @discardableResult
    private func assertMerges(
        _ before: String,
        replacing range: NSRange,
        with replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Reducer.Result? {
        let after = applying(range, replacement, to: before)
        let edit = Reducer.Edit(replacedRange: range, insertedLength: replacement.utf16.count)
        guard let result = Reducer.merge(state: fullState(before), text: after, edit: edit) else {
            XCTFail("expected an incremental merge", file: file, line: line)
            return nil
        }
        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after), file: file, line: line)
        assertFenceStatesMatch(result.state.lineFenceStates, after, "", file: file, line: line)
        return result
    }

    private func assertFallsBack(
        _ before: String,
        replacing range: NSRange,
        with replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let after = applying(range, replacement, to: before)
        let edit = Reducer.Edit(replacedRange: range, insertedLength: replacement.utf16.count)
        XCTAssertNil(Reducer.merge(state: fullState(before), text: after, edit: edit), file: file, line: line)
    }

    private func assertFenceStatesMatch(
        _ states: [Reducer.LineFenceState],
        _ text: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = Reducer.fenceStates(for: text)
        XCTAssertEqual(states.map(\.location), expected.map(\.location), message, file: file, line: line)
        XCTAssertEqual(states.map(\.fence.isInsideFence), expected.map(\.fence.isInsideFence), message, file: file, line: line)
    }

    private func fullState(_ text: String) -> Reducer.State {
        Reducer.State(tokens: NoteTokenScanner.scan(text), lineFenceStates: Reducer.fenceStates(for: text))
    }

    private func applying(_ range: NSRange, _ replacement: String, to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }

    /// Moves `location` off the middle of a surrogate pair, which no real edit produces and
    /// which would not survive the round trip through `String`.
    private static func safeBoundary(_ ns: NSString, _ location: Int) -> Int {
        guard location > 0, location < ns.length else { return location }
        let unit = ns.character(at: location)
        return (0xDC00...0xDFFF).contains(unit) ? location - 1 : location
    }
}

/// A small fixed-seed generator so the differential test replays the same edits every run.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }
}
