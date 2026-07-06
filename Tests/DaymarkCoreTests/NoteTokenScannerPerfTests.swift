import XCTest
@testable import DaymarkCore

// Timing budgets assert only under DAYMARK_PERF=1 so a loaded or CI machine never produces
// a false failure; the measurements print every run.
final class NoteTokenScannerPerfTests: XCTestCase {
    private var perfGateEnabled: Bool { ProcessInfo.processInfo.environment["DAYMARK_PERF"] == "1" }

    private func representativeNote(lines: Int) -> String {
        var out = ""
        out.reserveCapacity(lines * 40)
        for index in 0..<lines {
            switch index % 6 {
            case 0: out += "This is a plain body paragraph number \(index) with ordinary prose.\n"
            case 1: out += "- [ ] follow up on the report for section \(index)\n"
            case 2: out += "- [x] finished writing the summary for \(index)\n"
            case 3: out += "Some more narrative text describing the work done on \(index).\n"
            case 4: out += "## Heading \(index) with a #tag\(index) and a [[Link \(index)]]\n"
            default: out += "- [ ] ship item \(index) due:2026-07-08\n"
            }
        }
        return out
    }

    private func denseNote(lines: Int) -> String {
        var out = ""
        for index in 0..<lines {
            out += "- [ ] task \(index) due:2026-07-08 #work [[Ref \(index)]] https://ex.com/\(index)\n"
        }
        return out
    }

    func testFullScanSteadyStateOn5kLineNote() {
        let text = representativeNote(lines: 5000)
        _ = NoteTokenScanner.scan(text)
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<5 {
            let started = CFAbsoluteTimeGetCurrent()
            let tokens = NoteTokenScanner.scan(text)
            best = min(best, (CFAbsoluteTimeGetCurrent() - started) * 1000)
            XCTAssertEqual(tokens.lines.count, 5000)
        }
        NSLog("[perf] full scan 5k-line representative note (steady state best of 5): %.3f ms", best)
        if perfGateEnabled {
            XCTAssertLessThan(best, 40)
        }
    }

    func testDenseFullScanRecorded() {
        let text = denseNote(lines: 5000)
        _ = NoteTokenScanner.scan(text)
        let started = CFAbsoluteTimeGetCurrent()
        let tokens = NoteTokenScanner.scan(text)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
        NSLog("[perf] full scan 5k-line token-dense worst case (warmed): %.3f ms", elapsedMs)
        XCTAssertEqual(tokens.lines.count, 5000)
    }

    // This is the app's real sync-paragraph-restyle keystroke path (LiveRenderController):
    // fence state comes from the controller's cache, not a document walk, via the
    // fence-supplied scanLines overload. Budget: 1ms per the keystroke path requirement.
    func testParagraphScanIsCheapOn5kLines() {
        let text = representativeNote(lines: 5000)
        let ns = text as NSString
        let caret = ns.length / 2
        let paragraph = ns.lineRange(for: NSRange(location: caret, length: 0))
        // representativeNote never opens a fence, so the cache's fence state at any position is
        // the default (not inside a fence) -- exactly what LiveRenderController would have on hand.
        let fence = MarkdownFenceScanner()
        var worst = 0.0
        for _ in 0..<200 {
            let started = CFAbsoluteTimeGetCurrent()
            _ = NoteTokenScanner.scanLines(text, in: paragraph, fence: fence)
            worst = max(worst, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        NSLog("[perf] paragraph scanLines (fence-supplied, cached path) on 5k-line note (worst of 200): %.4f ms", worst)
        if perfGateEnabled {
            XCTAssertLessThan(worst, 1)
        }
    }

    // Characterizes the Finding 1 decision-rule measurement: the default scanLines overload
    // derives fence state by walking every line from the document start, so cost scales with
    // position. Measured ~5ms at document end on a 5k-line note, over the 0.5ms budget, which is
    // why the fence-supplied overload above exists and is what the app's hot path actually uses.
    // This default overload stays correct for any caller that does not track fence state itself;
    // it is not on the app's per-keystroke path, so it is characterized here, not budget-gated.
    func testFenceStatePrefixWalkCostAtDocumentEnd() {
        let text = representativeNote(lines: 5000)
        let ns = text as NSString
        let lastLine = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
        var worst = 0.0
        for _ in 0..<20 {
            let started = CFAbsoluteTimeGetCurrent()
            _ = NoteTokenScanner.scanLines(text, in: lastLine)
            worst = max(worst, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        NSLog("[perf] fence-state prefix walk (default overload) to document end on 5k-line note (worst of 20): %.4f ms", worst)
        // Sanity bound only: the walk must stay well under a full scan, never budget-gated at 1ms.
        if perfGateEnabled {
            XCTAssertLessThan(worst, 20)
        }
    }

    // Isolates the overload that skips the walk entirely, for comparison against the number above.
    func testFenceSuppliedOverloadSkipsWalkCost() {
        let text = representativeNote(lines: 5000)
        let ns = text as NSString
        let lastLine = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
        let fence = MarkdownFenceScanner()
        var worst = 0.0
        for _ in 0..<200 {
            let started = CFAbsoluteTimeGetCurrent()
            _ = NoteTokenScanner.scanLines(text, in: lastLine, fence: fence)
            worst = max(worst, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        NSLog("[perf] fence-supplied scanLines at document end on 5k-line note (worst of 200): %.4f ms", worst)
        if perfGateEnabled {
            XCTAssertLessThan(worst, 1)
        }
    }
}
