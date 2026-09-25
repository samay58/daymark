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

        // Every line is "- [ ] task N due:2026-07-08 #work [[Ref N]] https://ex.com/N", so a
        // correct dense scan must find exactly one of each inline token kind per line, not just
        // the right line count (a scanner that dropped inline scanning entirely would still
        // pass the line-count-only assertion this replaces).
        let taskLines = tokens.lines.filter { if case .task = $0.kind { return true } else { return false } }
        XCTAssertEqual(taskLines.count, 5000)
        let dueTokens = tokens.inlineTokens.filter { if case .dueDate = $0.kind { return true } else { return false } }
        XCTAssertEqual(dueTokens.count, 5000)
        XCTAssertEqual(tokens.inlineTokens.filter { $0.kind == .tag }.count, 5000)
        XCTAssertEqual(tokens.inlineTokens.filter { $0.kind == .wikilink }.count, 5000)
        XCTAssertEqual(tokens.inlineTokens.filter { $0.kind == .url }.count, 5000)
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

    // The default scanLines overload derives fence state by walking from the document start.
    // That path stays correct for generic callers, but it is not the editor's per-keystroke path.
    func testFenceSuppliedScanAvoidsPrefixWalkAtDocumentEnd() {
        let text = representativeNote(lines: 5000)
        let ns = text as NSString
        let lastLine = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
        let fence = MarkdownFenceScanner()

        var defaultBest = Double.greatestFiniteMagnitude
        var suppliedBest = Double.greatestFiniteMagnitude
        for _ in 0..<10 {
            var started = CFAbsoluteTimeGetCurrent()
            _ = NoteTokenScanner.scanLines(text, in: lastLine)
            defaultBest = min(defaultBest, (CFAbsoluteTimeGetCurrent() - started) * 1000)

            started = CFAbsoluteTimeGetCurrent()
            _ = NoteTokenScanner.scanLines(text, in: lastLine, fence: fence)
            suppliedBest = min(suppliedBest, (CFAbsoluteTimeGetCurrent() - started) * 1000)
        }

        NSLog(
            "[perf] document-end scanLines default best %.4f ms; fence-supplied best %.4f ms",
            defaultBest,
            suppliedBest
        )
        if perfGateEnabled {
            XCTAssertLessThan(suppliedBest, defaultBest * 0.5)
            XCTAssertLessThan(suppliedBest, 1)
        }
    }
}
