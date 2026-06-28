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
}
