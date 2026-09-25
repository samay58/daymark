import XCTest
@testable import DaymarkCore

/// Covers the "machine text never renders raw" scanner support: the rollover HTML comment
/// marker and the `(from <path>:<line>)` provenance parenthetical are detected as inline
/// tokens so the live render can conceal them. Ranges must be exact (UTF-16, emoji-safe),
/// fence-aware, and CRLF-safe, and must not fire on ordinary prose.
final class MachineTextConcealmentTests: XCTestCase {
    private func tokens(_ tokens: NoteTokens, _ kind: (NoteTokens.InlineKind) -> Bool) -> [NoteTokens.InlineToken] {
        tokens.inlineTokens.filter { kind($0.kind) }
    }

    private func markers(_ t: NoteTokens) -> [NoteTokens.InlineToken] {
        tokens(t) { if case .rolloverMarker = $0 { return true } else { return false } }
    }

    private func provenances(_ t: NoteTokens) -> [NoteTokens.InlineToken] {
        tokens(t) { if case .provenance = $0 { return true } else { return false } }
    }

    private static let marker = "<!-- daymark-rollover:6b86b273ff34fce -->"

    func testDetectsMarkerAndProvenanceOnRolloverLine() {
        let md = "- Rolled over: ship the demo (from daily/2026/07/2026-07-04.md:12) \(Self.marker)"
        let t = NoteTokenScanner.scan(md)
        let ns = md as NSString

        let m = markers(t)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(ns.substring(with: m[0].range), Self.marker)

        let p = provenances(t)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(ns.substring(with: p[0].range), "(from daily/2026/07/2026-07-04.md:12)")
    }

    func testProvenanceRequiresLineNumber() {
        // A parenthetical without a trailing :<digits> is not provenance and stays literal.
        let md = "- Rolled over: ship it (from somewhere) \(Self.marker)"
        let t = NoteTokenScanner.scan(md)
        XCTAssertEqual(markers(t).count, 1)
        XCTAssertTrue(provenances(t).isEmpty)
    }

    func testOrdinaryProseNotConcealed() {
        // No rollover marker on the line, so a provenance-shaped parenthetical is left alone.
        let md = "- note copied (from report.md:4) for later"
        let t = NoteTokenScanner.scan(md)
        XCTAssertTrue(markers(t).isEmpty)
        XCTAssertTrue(provenances(t).isEmpty)
    }

    func testNotDetectedInsideFence() {
        let md = """
        ```
        - Rolled over: ship it (from daily/2026/07/2026-07-04.md:12) \(Self.marker)
        ```
        """
        let t = NoteTokenScanner.scan(md)
        XCTAssertTrue(markers(t).isEmpty)
        XCTAssertTrue(provenances(t).isEmpty)
    }

    func testCRLFSafe() {
        let md = "- Rolled over: ship it (from daily/2026/07/2026-07-04.md:12) \(Self.marker)\r\nnext line"
        let t = NoteTokenScanner.scan(md)
        let ns = md as NSString
        let m = markers(t)
        XCTAssertEqual(m.count, 1)
        // The range must stop at `-->`, never swallowing the CRLF terminator.
        XCTAssertEqual(ns.substring(with: m[0].range), Self.marker)
        XCTAssertEqual(provenances(t).count, 1)
    }

    func testEmojiSafeRanges() {
        // Emoji before the machine text are surrogate pairs (two UTF-16 units each); the
        // NSRange the scanner returns must still land exactly on the marker and provenance.
        let md = "- Rolled over: 🚀 launch 🎯 (from daily/2026/07/2026-07-04.md:12) \(Self.marker)"
        let t = NoteTokenScanner.scan(md)
        let ns = md as NSString

        let m = markers(t)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(ns.substring(with: m[0].range), Self.marker)

        let p = provenances(t)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(ns.substring(with: p[0].range), "(from daily/2026/07/2026-07-04.md:12)")
    }

    func testMarkerConcealmentSurvivesIncrementalRescan() {
        // The incremental line scanner (used on every keystroke) must produce the same tokens
        // as a full scan, so concealment does not blink while typing on the line.
        let md = "- Rolled over: ship it (from daily/2026/07/2026-07-04.md:12) \(Self.marker)\nafter"
        let ns = md as NSString
        let lineRange = ns.lineRange(for: NSRange(location: 0, length: 0))
        let incremental = scanLinesWithCachedFence(md, in: lineRange)

        let m = incremental.inlineTokens.filter { if case .rolloverMarker = $0.kind { return true } else { return false } }
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(ns.substring(with: m[0].range), Self.marker)
        let p = incremental.inlineTokens.filter { if case .provenance = $0.kind { return true } else { return false } }
        XCTAssertEqual(p.count, 1)
    }

    func testRealRolloverPlanLineIsConcealable() {
        // End-to-end against the actual TaskRollover output format, so the concealment tracks
        // the engine even if the exact marker string evolves.
        let task = TaskItem(
            title: "finish the spike",
            status: .open,
            notePath: "daily/2026/07/2026-07-04.md",
            lineNumber: 7,
            originalLine: "- [ ] finish the spike"
        )
        let plan = TaskRollover.plan(
            tasks: [task],
            todayMarkdown: "# Today\n\n## Brief\n",
            todayPath: "daily/2026/07/2026-07-05.md"
        )
        XCTAssertEqual(plan.entries.count, 1)

        let t = NoteTokenScanner.scan(plan.updatedMarkdown)
        let ns = plan.updatedMarkdown as NSString

        let m = markers(t)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(ns.substring(with: m[0].range), plan.entries[0].marker)

        let p = provenances(t)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(ns.substring(with: p[0].range), "(from daily/2026/07/2026-07-04.md:7)")
    }

    func testConcealmentTokensDoNotDisturbInlineTokensOnSameLine() {
        // A real #tag in the rolled-over title still scans; the machine-text detection is
        // additive and does not swallow or shift other inline tokens.
        let md = "- Rolled over: ship #launch demo (from daily/2026/07/2026-07-04.md:12) \(Self.marker)"
        let t = NoteTokenScanner.scan(md)
        let ns = md as NSString
        let tags = t.inlineTokens.filter { if case .tag = $0.kind { return true } else { return false } }
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(ns.substring(with: tags[0].range), "#launch")
        XCTAssertEqual(markers(t).count, 1)
        XCTAssertEqual(provenances(t).count, 1)
    }
}
