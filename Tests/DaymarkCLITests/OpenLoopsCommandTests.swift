import XCTest

/// End-to-end tests for `daymark open-loops` against a temporary workspace. They never touch
/// the real `~/phoenix`, and are skipped when the product is not built (`swift build` first).
final class OpenLoopsCommandTests: XCTestCase {
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
        try XCTSkipIf(binaryURL == nil, "daymark binary not built; run `swift build` before `swift test`")
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-loops-\(UUID().uuidString)"
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

    func testOpenLoopsListsOpenTasksAndExcludesCompleted() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Yesterday

        ## Capture

        - [ ] follow up with the vendor
        - [x] already filed the report
        """, named: "2026-06-27.md", in: root)
        try writeDaily("""
        # Today

        ## Capture

        - [ ] review the memo
        """, named: "2026-06-28.md", in: root)

        let rebuild = try runDaymark(["rebuild", "--root", root])
        XCTAssertEqual(rebuild.status, 0, rebuild.output)

        let result = try runDaymark(["open-loops", "--root", root])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("follow up with the vendor"), result.output)
        XCTAssertTrue(result.output.contains("review the memo"), result.output)
        XCTAssertFalse(result.output.contains("already filed the report"), "completed tasks must not appear: \(result.output)")
    }

    func testOpenLoopsGroupsTasksIntoBuckets() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        ## Capture

        - [ ] ship the release due:today
        - [ ] someday idea
        """, named: "2026-06-28.md", in: root)

        _ = try runDaymark(["rebuild", "--root", root])
        let result = try runDaymark(["open-loops", "--root", root])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Due today"), result.output)
        XCTAssertTrue(result.output.contains("No date"), result.output)
    }

    func testOpenLoopsReflectsMarkdownWithoutPriorRebuild() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("## Capture\n\n- [ ] fresh open task\n", named: "2026-06-28.md", in: root)
        // No `rebuild` first: open-loops now reads fresh from the Markdown files.
        let result = try runDaymark(["open-loops", "--root", root])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("fresh open task"),
                      "open-loops should reflect the files on disk without a prior rebuild: \(result.output)")
    }

    func testOpenLoopsDropsTaskAfterSourceNoteDeleted() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("## Capture\n\n- [ ] keep this\n", named: "2026-06-27.md", in: root)
        try writeDaily("## Capture\n\n- [ ] remove this\n", named: "2026-06-28.md", in: root)

        let before = try runDaymark(["open-loops", "--root", root])
        XCTAssertTrue(before.output.contains("keep this"), before.output)
        XCTAssertTrue(before.output.contains("remove this"), before.output)

        try FileManager.default.removeItem(atPath: "\(root)/daily/2026/06/2026-06-28.md")
        let after = try runDaymark(["open-loops", "--root", root])
        XCTAssertTrue(after.output.contains("keep this"), after.output)
        XCTAssertFalse(after.output.contains("remove this"),
                       "a deleted note's task must not appear: \(after.output)")
    }

    func testOpenLoopsReportsWhenNothingIsOpen() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["open-loops", "--root", root])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.lowercased().contains("no open"), result.output)
    }
}
