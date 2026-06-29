import XCTest
@testable import DaymarkCore

final class DailyNoteStoreTests: XCTestCase {
    private func makeRoot() -> WorkspaceRoot {
        let dir = "\(NSTemporaryDirectory())daymark-store-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return WorkspaceRoot(path: dir)
    }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return c
    }

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.hour = 12
        return cal.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func testEnsureCreatesTodayNoteWhenMissing() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        let result = try store.ensureTodayNote(date: fixedDate())

        XCTAssertTrue(result.created)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertTrue(result.url.path.hasSuffix("daily/2026/06/2026-06-28.md"))
        XCTAssertTrue(try String(contentsOf: result.url, encoding: .utf8).contains("## Brief"))
    }

    func testEnsureDoesNotOverwriteExistingNote() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        let first = try store.ensureTodayNote(date: fixedDate())
        try AtomicFileWriter().write("# user edited content", to: first.url)

        let second = try store.ensureTodayNote(date: fixedDate())
        XCTAssertFalse(second.created)
        XCTAssertEqual(try String(contentsOf: second.url, encoding: .utf8), "# user edited content")
    }

    func testLoadReturnsTodayContents() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        _ = try store.ensureTodayNote(date: fixedDate())
        try store.save("# edited\n\n## Brief\n", date: fixedDate())
        XCTAssertEqual(try store.loadToday(date: fixedDate()), "# edited\n\n## Brief\n")
    }

    func testSaveWritesAtomically() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        try store.save("# only this", date: fixedDate())
        let url = store.todayFileURL(date: fixedDate())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# only this")
    }

    func testAppendCaptureCreatesNoteAndAddsUnderCapture() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        let url = try store.appendCapture("a quick thought", date: fixedDate())

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("## Capture"))
        XCTAssertTrue(contents.contains("- 12:00 a quick thought"))
        XCTAssertTrue(contents.contains("## Decisions"), "template sections are preserved")
    }

    func testAppendCapturePreservesExistingContentAndHeadings() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        _ = try store.ensureTodayNote(date: fixedDate())
        try store.appendCapture("first", date: fixedDate())
        let url = try store.appendCapture("second", date: fixedDate())

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents.components(separatedBy: "## Capture").count - 1, 1, "no duplicate Capture heading")
        XCTAssertTrue(contents.contains("first"))
        XCTAssertTrue(contents.contains("second"))
        XCTAssertTrue(contents.contains("## End of day"), "later sections survive repeated appends")
    }

    func testAppendTaskWritesOpenMarkdownTaskLine() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        let url = try store.appendTask("write the spec", date: fixedDate())

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("- [ ] write the spec"))
        // The task line must parse back as an open task.
        let tasks = TaskParser().parse(markdown: contents)
        XCTAssertTrue(tasks.contains { $0.title == "write the spec" && $0.status == .open })
    }

    func testAppendEmptyCaptureThrowsAndDoesNotCreateNote() {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        XCTAssertThrowsError(try store.appendCapture("   ", date: fixedDate())) { error in
            XCTAssertEqual(error as? CaptureError, .empty)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.todayFileURL(date: fixedDate()).path))
    }

    func testAppendCaptureAddsHeadingWhenNoteHasNoCaptureSection() throws {
        let store = DailyNoteStore(root: makeRoot(), calendar: cal)
        // A note the user wrote with no Capture section at all.
        try store.save("# Custom note\n\nJust prose, no sections.\n", date: fixedDate())

        let url = try store.appendCapture("a thought", date: fixedDate())
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("Just prose, no sections."), "existing content is preserved")
        XCTAssertTrue(contents.contains("## Capture"), "a Capture heading is added")
        XCTAssertTrue(contents.contains("a thought"))
    }
}
