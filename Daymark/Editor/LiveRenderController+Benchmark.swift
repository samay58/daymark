#if DEBUG
import AppKit
import DaymarkCore

// A debug-only latency harness for the keystroke, concealment, and card-reposition paths. It is
// compiled out of release builds and does nothing unless DAYMARK_BENCH=1. It drives the
// controller against a 5k-line note (run it against a scratch workspace only). Every buffer edit
// it makes to time the sync path is a matched insert and remove that restores the buffer.
extension LiveRenderController {
    /// Silences the per-keystroke timing log while the benchmark runs, since that log sits inside
    /// the timed path.
    static var benchmarkRunning = false

    func runBenchmarkIfRequested() {
        guard ProcessInfo.processInfo.environment["DAYMARK_BENCH"] == "1" else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            Self.benchmarkRunning = true
            self?.runBenchmark()
            Self.benchmarkRunning = false
        }
    }

    private func runBenchmark() {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        guard ns.length > 200 else { return }

        var probe = ns.length / 2
        while probe < ns.length {
            let line = ns.lineRange(for: NSRange(location: probe, length: 0))
            if ns.range(of: "due:", options: [], range: line).location != NSNotFound { probe = line.location; break }
            probe = line.location + max(1, line.length)
        }
        let line = ns.lineRange(for: NSRange(location: probe, length: 0))
        let insertLoc = line.location + min(6, max(0, line.length - 1))

        func stats(_ times: [Double]) -> (median: Double, p95: Double) {
            let sorted = times.sorted()
            return (sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)])
        }

        // Incremental cache correctness: after a net-zero edit the cache must still equal a fresh
        // full scan, or a decoration is stale until the next debounced pass.
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: "Z")
        textView.setSelectedRange(NSRange(location: insertLoc + 1, length: 0))
        styleEditedParagraph()
        storage.replaceCharacters(in: NSRange(location: insertLoc, length: 1), with: "")
        textView.setSelectedRange(NSRange(location: insertLoc, length: 0))
        styleEditedParagraph()
        NSLog("[Daymark][BENCH] incremental cache equals fresh scan after edit: %@", (NoteTokenScanner.scan(storage.string) == cachedTokens) ? "yes" : "no")

        var syncTimes: [Double] = []
        for _ in 0..<300 {
            textView.setSelectedRange(NSRange(location: insertLoc, length: 0))
            storage.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: "x")
            textView.setSelectedRange(NSRange(location: insertLoc + 1, length: 0))
            let t = CFAbsoluteTimeGetCurrent()
            styleEditedParagraph()
            syncTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            storage.replaceCharacters(in: NSRange(location: insertLoc, length: 1), with: "")
            styleEditedParagraph()
        }
        let sync = stats(syncTimes)
        NSLog("[Daymark][BENCH] sync keystroke: median %.3f ms  p95 %.3f ms  (%d lines)", sync.median, sync.p95, cachedTokens.lines.count)

        let a = NSRange(location: insertLoc, length: 0)
        let b = NSRange(location: line.location + line.length + 1, length: 0)
        var reconcileTimes: [Double] = []
        for i in 0..<300 {
            textView.setSelectedRange(i % 2 == 0 ? a : b)
            resetConcealmentBaseline(to: i % 2 == 0 ? b : a)
            let t = CFAbsoluteTimeGetCurrent()
            reconcileConcealment()
            reconcileTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        let reconcile = stats(reconcileTimes)
        NSLog("[Daymark][BENCH] reconcileConcealment: median %.3f ms  p95 %.3f ms", reconcile.median, reconcile.p95)

        if let cardController {
            var repoTimes: [Double] = []
            for _ in 0..<100 {
                let t = CFAbsoluteTimeGetCurrent()
                cardController.repositionCards()
                repoTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            }
            let repo = stats(repoTimes)
            NSLog("[Daymark][BENCH] repositionCards: median %.3f ms  p95 %.3f ms", repo.median, repo.p95)
        }
        NSLog("[Daymark][BENCH] done")
    }
}
#endif
