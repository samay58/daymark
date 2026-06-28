import XCTest
@testable import DaymarkIndexer

final class FileWatcherTests: XCTestCase {
    private func makeTempDir() throws -> String {
        let dir = "\(NSTemporaryDirectory())daymark-watch-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    func testWatcherReportsNewFile() throws {
        let dir = try makeTempDir()
        let expectation = expectation(description: "file change observed")
        let target = "\(dir)/note.md"

        let watcher = FileWatcher(paths: [dir], latency: 0.05) { paths in
            if paths.contains(where: { $0.hasSuffix("note.md") }) {
                expectation.fulfill()
            }
        }
        watcher.start()
        addTeardownBlock { watcher.stop() }

        // FSEvents needs the stream to be live before the write; a brief delay avoids a race.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? "# Hello\n".write(toFile: target, atomically: true, encoding: .utf8)
        }

        wait(for: [expectation], timeout: 10)
    }

    func testWatcherReportsModification() throws {
        let dir = try makeTempDir()
        let target = "\(dir)/note.md"
        try "v1\n".write(toFile: target, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "modification observed")
        let watcher = FileWatcher(paths: [dir], latency: 0.05) { paths in
            if paths.contains(where: { $0.hasSuffix("note.md") }) {
                expectation.fulfill()
            }
        }
        watcher.start()
        addTeardownBlock { watcher.stop() }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? "v2 changed\n".write(toFile: target, atomically: true, encoding: .utf8)
        }

        wait(for: [expectation], timeout: 10)
    }
}
