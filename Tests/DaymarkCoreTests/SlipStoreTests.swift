import XCTest
@testable import DaymarkCore

final class SlipStoreTests: XCTestCase {
    private func makeRoot() -> WorkspaceRoot {
        let dir = "\(NSTemporaryDirectory())daymark-slip-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return WorkspaceRoot(path: dir)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return c
    }

    private func dateAt(day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func testMonthlyRelativePathIsYearMonth() {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        XCTAssertEqual(store.monthlyRelativePath(for: dateAt(day: 28, hour: 9, minute: 30)), "slip/2026-06.md")
    }

    func testSaveCreatesMonthlyFileWithDayHeadingAndBullet() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        let url = try store.save("remember the milk", date: dateAt(day: 28, hour: 9, minute: 30))

        XCTAssertTrue(url.path.hasSuffix("slip/2026-06.md"))
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("## 2026-06-28"), "captures are grouped under a day heading")
        XCTAssertTrue(contents.contains("- 09:30 remember the milk"))
    }

    func testSaveAppendsToSameDayWithoutDuplicatingHeading() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        let day = dateAt(day: 28, hour: 9, minute: 30)
        _ = try store.save("first", date: day)
        let url = try store.save("second", date: dateAt(day: 28, hour: 10, minute: 15))

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents.components(separatedBy: "## 2026-06-28").count - 1, 1, "one day heading")
        XCTAssertTrue(contents.contains("- 09:30 first"))
        XCTAssertTrue(contents.contains("- 10:15 second"))
        let firstRange = contents.range(of: "- 09:30 first")!
        let secondRange = contents.range(of: "- 10:15 second")!
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
    }

    func testSaveMultilineCaptureStaysReadable() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        let url = try store.save("line one\nline two", date: dateAt(day: 28, hour: 9, minute: 30))
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("- 09:30 line one\n  line two"))
    }

    func testSaveEmptyCaptureThrowsAndWritesNothing() {
        let root = makeRoot()
        let store = SlipStore(root: root, calendar: calendar)
        XCTAssertThrowsError(try store.save("   \n  ", date: dateAt(day: 28, hour: 9, minute: 30))) { error in
            XCTAssertEqual(error as? CaptureError, .empty)
        }
        let monthly = store.monthlyFileURL(for: dateAt(day: 28, hour: 9, minute: 30))
        XCTAssertFalse(FileManager.default.fileExists(atPath: monthly.path), "discarded capture writes no file")
    }

    func testSaveGroupsCapturesByDay() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        _ = try store.save("earlier day", date: dateAt(day: 28, hour: 9, minute: 0))
        let url = try store.save("later day", date: dateAt(day: 29, hour: 8, minute: 0))

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents.components(separatedBy: "## 2026-06-28").count - 1, 1)
        XCTAssertEqual(contents.components(separatedBy: "## 2026-06-29").count - 1, 1)
        let earlier = contents.range(of: "earlier day")!
        let later = contents.range(of: "later day")!
        XCTAssertTrue(earlier.lowerBound < later.lowerBound, "day sections stay in write order")
    }

    func testSaveDoesNotClobberFileItCannotRead() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        let date = dateAt(day: 28, hour: 9, minute: 30)
        let url = store.monthlyFileURL(for: date)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // An existing slip file that is not valid UTF-8 (corruption or an external tool).
        let invalid = Data([0xFF, 0xFE, 0x00, 0x01, 0xFF])
        try invalid.write(to: url)

        XCTAssertThrowsError(try store.save("new capture", date: date),
                             "an unreadable existing file must not be silently overwritten")
        let after = try Data(contentsOf: url)
        XCTAssertEqual(after, invalid, "the original bytes are preserved when the read fails")
    }

    func testSaveRestoresTitleWhenFileIsEmpty() throws {
        let store = SlipStore(root: makeRoot(), calendar: calendar)
        let date = dateAt(day: 28, hour: 9, minute: 30)
        let url = store.monthlyFileURL(for: date)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("".utf8).write(to: url)

        _ = try store.save("first", date: date)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("# Slip"), "an empty slip file gets its title restored")
        XCTAssertTrue(contents.contains("- 09:30 first"))
    }
}
