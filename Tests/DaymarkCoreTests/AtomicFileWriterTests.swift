import XCTest
@testable import DaymarkCore

final class AtomicFileWriterTests: XCTestCase {
    private func makeTempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("daymark-aw-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testWritesExactContents() throws {
        let url = makeTempDir().appendingPathComponent("note.md")
        try AtomicFileWriter().write("hello world", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello world")
    }

    func testCreatesIntermediateDirectories() throws {
        let url = makeTempDir().appendingPathComponent("daily/2026/06/2026-06-28.md")
        try AtomicFileWriter().write("# Today", to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testOverwriteFullyReplacesLongerPreviousContents() throws {
        let url = makeTempDir().appendingPathComponent("note.md")
        let writer = AtomicFileWriter()
        try writer.write("a very long original line of text", to: url)
        try writer.write("short", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "short")
    }

    func testLeavesNoTempSiblingsBehind() throws {
        let dir = makeTempDir()
        let url = dir.appendingPathComponent("note.md")
        try AtomicFileWriter().write("content", to: url)
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(entries, ["note.md"], "atomic write should not leak temp files")
    }
}
