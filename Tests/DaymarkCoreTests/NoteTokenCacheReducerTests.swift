import XCTest
@testable import DaymarkCore

final class NoteTokenCacheReducerTests: XCTestCase {
    func testEditAboveRegionShiftsRegionAndFenceState() {
        let before = """
        intro
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        generated
        <!-- daymark:block-end abc123 -->
        tail
        """
        let after = """
        intro updated
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        generated
        <!-- daymark:block-end abc123 -->
        tail
        """
        let nsAfter = after as NSString
        let editedLine = nsAfter.lineRange(for: NSRange(location: 0, length: 0))
        let result = merge(before: before, after: after, editedRange: editedLine)

        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after))
        XCTAssertEqual(result.delta, " updated".count)
        XCTAssertEqual(result.state.lineFenceStates.map(\.location), NoteTokenCacheReducer.fenceStates(for: after).map(\.location))
    }

    func testDeleteAboveRegionShiftsRegionAndFenceState() {
        let before = """
        intro extra
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        generated
        <!-- daymark:block-end abc123 -->
        tail
        """
        let after = """
        intro
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        generated
        <!-- daymark:block-end abc123 -->
        tail
        """
        let nsAfter = after as NSString
        let editedLine = nsAfter.lineRange(for: NSRange(location: 0, length: 0))
        let result = merge(before: before, after: after, editedRange: editedLine)

        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after))
        XCTAssertLessThan(result.delta, 0)
        XCTAssertEqual(result.state.lineFenceStates.map(\.location), NoteTokenCacheReducer.fenceStates(for: after).map(\.location))
    }

    func testPasteMultipleLinesShiftsDownstreamTokens() {
        let before = """
        alpha
        - [ ] beta due:today
        - [ ] gamma due:tomorrow
        """
        let after = """
        alpha
        - [ ] beta plus due:today
        inserted #tag
        second inserted [[Link]]
        - [ ] gamma due:tomorrow
        """
        let nsAfter = after as NSString
        let editStart = nsAfter.range(of: "- [ ] beta").location
        let editEnd = nsAfter.range(of: "- [ ] gamma").location
        let editedRange = NSRange(location: editStart, length: editEnd - editStart)
        let result = merge(before: before, after: after, editedRange: editedRange)

        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after))
        XCTAssertGreaterThan(result.delta, 0)
    }

    func testShiftKeyedRangesDropsEditedRangeAndMovesFollowingRanges() {
        let ranges = [
            NoteTokenCacheReducer.KeyedRange(key: 5, range: NSRange(location: 5, length: 3)),
            NoteTokenCacheReducer.KeyedRange(key: 20, range: NSRange(location: 20, length: 4)),
            NoteTokenCacheReducer.KeyedRange(key: 40, range: NSRange(location: 40, length: 2))
        ]

        let shifted = NoteTokenCacheReducer.shiftKeyedRanges(
            ranges,
            editStart: 10,
            oldParagraphEnd: 30,
            delta: 7
        )

        XCTAssertEqual(shifted.map(\.key), [5, 47])
        XCTAssertEqual(shifted.map(\.range.location), [5, 47])
    }

    func testFenceMarkerEditRequiresFullPass() {
        let text = "`\n- [ ] hidden\n```\n- [ ] visible\n"
        XCTAssertFalse(NoteTokenCacheReducer.canMergeIncrementally(
            text: text,
            editedRange: NSRange(location: 0, length: 1)
        ))
    }

    func testNonFenceEditCanMergeIncrementally() {
        let text = "plain\n- [ ] visible due:today\n"
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: ns.range(of: "visible").location, length: 0))
        XCTAssertTrue(NoteTokenCacheReducer.canMergeIncrementally(text: text, editedRange: line))
    }

    private func merge(before: String, after: String, editedRange: NSRange) -> NoteTokenCacheReducer.Result {
        let rescanned = NoteTokenScanner.scanLines(after, in: editedRange)
        let state = NoteTokenCacheReducer.State(
            tokens: NoteTokenScanner.scan(before),
            lineFenceStates: NoteTokenCacheReducer.fenceStates(for: before)
        )
        return NoteTokenCacheReducer.merge(state: state, rescanned: rescanned, editedRange: editedRange)
    }
}
