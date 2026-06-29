import XCTest

final class DynamicBlocksCommandTests: XCTestCase {
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
        try XCTSkipIf(binaryURL == nil, "daymark binary not built; run `swift build` before this test")
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-blocks-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ markdown: String, relativePath: String, root: String) throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relativePath: String, root: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relativePath), encoding: .utf8)
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

    func testBlocksRefreshDryRunAndApplyAreIdempotent() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        try write("""
        # Yesterday

        - [ ] call Sarah #deal/acme due:today
        - [x] already sent the note #deal/acme
        - [ ] review beta draft #deal/beta
        """, relativePath: "daily/2026/06/2026-06-28.md", root: root)
        try write("""
        Intro stays.
        /daymark open-loops #deal/acme
        Outro stays.
        """, relativePath: sourcePath, root: root)

        let original = try read(sourcePath, root: root)
        let dryRun = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--date", "2026-06-29"])
        XCTAssertEqual(dryRun.status, 0, dryRun.output)
        XCTAssertTrue(dryRun.output.contains("Target: \(sourcePath)"), dryRun.output)
        XCTAssertTrue(dryRun.output.contains("Operation: insert"), dryRun.output)
        XCTAssertTrue(dryRun.output.contains("call Sarah #deal/acme due:today"), dryRun.output)
        XCTAssertFalse(dryRun.output.contains("already sent the note"), dryRun.output)
        XCTAssertEqual(try read(sourcePath, root: root), original)
        let cachePath = "\(root)/.daymark/dynamic-blocks.json"
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachePath))

        let apply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--date", "2026-06-29", "--apply"])
        XCTAssertEqual(apply.status, 0, apply.output)
        let applied = try read(sourcePath, root: root)
        XCTAssertTrue(applied.contains("Intro stays."))
        XCTAssertTrue(applied.contains("/daymark open-loops #deal/acme"))
        XCTAssertTrue(applied.contains("Outro stays."))
        XCTAssertEqual(applied.components(separatedBy: "daymark:block-begin").count - 1, 1)
        XCTAssertEqual(applied.components(separatedBy: "call Sarah #deal/acme due:today").count - 1, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath))
        let cache = try String(contentsOfFile: cachePath, encoding: .utf8)
        let cacheObject = try JSONSerialization.jsonObject(with: Data(cache.utf8)) as? [String: Any]
        let records = try XCTUnwrap(cacheObject?["records"] as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["sourcePath"] as? String, sourcePath)
        XCTAssertEqual(record["rendererName"] as? String, "open-loops")
        XCTAssertNotNil(record["renderedOutputHash"])

        try? FileManager.default.removeItem(atPath: "\(root)/.daymark")
        let repeatApply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--date", "2026-06-29", "--apply"])
        XCTAssertEqual(repeatApply.status, 0, repeatApply.output)
        XCTAssertEqual(try read(sourcePath, root: root), applied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath))
    }
}
