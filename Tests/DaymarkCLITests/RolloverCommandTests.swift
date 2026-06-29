import XCTest

/// End-to-end tests for `daymark rollover` against temporary workspaces only.
final class RolloverCommandTests: XCTestCase {
    private var binaryURL: URL? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildDirectory = repoRoot.appendingPathComponent(".build", isDirectory: true)
        let candidates = [
            "arm64-apple-macosx/debug/daymark",
            "debug/daymark",
            "arm64-apple-macosx/release/daymark",
            "release/daymark"
        ]
        for relativePath in candidates {
            let candidate = buildDirectory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func skipIfBinaryMissing() throws {
        try XCTSkipIf(binaryURL == nil, "daymark binary not built; run `swift build --product daymark` before this test")
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-rollover-cli-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func writeDaily(_ markdown: String, named name: String, in root: String) throws {
        let url = URL(fileURLWithPath: "\(root)/daily/2026/06/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func runDaymark(_ arguments: [String], timeout: TimeInterval = 20) throws -> (output: String, status: Int32) {
        let binaryURL = try XCTUnwrap(binaryURL, "daymark binary not found")
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        let inPipe = Pipe()
        process.standardInput = inPipe
        inPipe.fileHandleForWriting.closeFile()
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            XCTFail("daymark \(arguments.joined(separator: " ")) timed out after \(timeout)s")
            return ("timeout", -1)
        }
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    func testRolloverAppliesOpenPriorTasksOnce() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Yesterday

        ## Capture

        - [ ] follow up with Sarah #deal/acme
        - [x] already sent the report
        """, named: "2026-06-27.md", in: root)
        try writeDaily("""
        # Today

        ## Brief

        ## Capture
        """, named: "2026-06-28.md", in: root)
        let originalYesterday = try String(contentsOfFile: "\(root)/daily/2026/06/2026-06-27.md", encoding: .utf8)

        let first = try runDaymark(["rollover", "--date", "2026-06-28", "--apply", "--root", root])
        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertTrue(first.output.contains("Rolled over 1 task"), first.output)

        let second = try runDaymark(["rollover", "--date", "2026-06-28", "--apply", "--root", root])
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("No tasks to roll over"), second.output)

        let today = try String(contentsOfFile: "\(root)/daily/2026/06/2026-06-28.md", encoding: .utf8)
        XCTAssertEqual(today.components(separatedBy: "Rolled over: follow up with Sarah").count - 1, 1)
        XCTAssertFalse(today.contains("already sent the report"))
        XCTAssertTrue(today.contains("<!-- daymark-rollover:"))
        XCTAssertEqual(try String(contentsOfFile: "\(root)/daily/2026/06/2026-06-27.md", encoding: .utf8), originalYesterday)
    }

    func testRolloverDoesNotDuplicateAfterDatabaseRebuild() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Yesterday

        ## Capture

        - [ ] renew the vendor agreement
        """, named: "2026-06-27.md", in: root)
        try writeDaily("""
        # Today

        ## Brief

        ## Capture
        """, named: "2026-06-28.md", in: root)

        XCTAssertEqual(try runDaymark(["rollover", "--date", "2026-06-28", "--apply", "--root", root]).status, 0)

        let dbPath = "\(root)/.daymark/daymark.db"
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))

        XCTAssertEqual(try runDaymark(["rebuild", "--root", root]).status, 0)
        let second = try runDaymark(["rollover", "--date", "2026-06-28", "--apply", "--root", root])
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("No tasks to roll over"), second.output)

        let today = try String(contentsOfFile: "\(root)/daily/2026/06/2026-06-28.md", encoding: .utf8)
        XCTAssertEqual(today.components(separatedBy: "Rolled over: renew the vendor agreement").count - 1, 1)
    }
}
