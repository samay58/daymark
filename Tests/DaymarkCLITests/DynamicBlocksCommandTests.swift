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

    func testBlocksRefreshRejectsParentEscapeSource() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try write("Intro\n/daymark open-loops\n", relativePath: "daily/2026/06/2026-06-29.md", root: root)
        let outsideURL = URL(fileURLWithPath: root).deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try "/daymark open-loops\nimportant outside content\n".write(to: outsideURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: outsideURL) }
        let before = try String(contentsOf: outsideURL, encoding: .utf8)

        let result = try runDaymark(["blocks", "refresh", "--root", root,
                                     "--source", "../\(outsideURL.lastPathComponent)", "--apply"])
        XCTAssertNotEqual(result.status, 0, "a parent-escape source must be rejected: \(result.output)")
        XCTAssertTrue(result.output.lowercased().contains("outside the workspace"), result.output)
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), before,
                       "the file outside the workspace must be untouched")
    }

    func testBlocksRefreshRejectsAbsoluteOutsideSource() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let outsideURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("daymark-abs-\(UUID().uuidString).md")
        try "/daymark open-loops\nabsolute outside content\n".write(to: outsideURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: outsideURL) }
        let before = try String(contentsOf: outsideURL, encoding: .utf8)

        let result = try runDaymark(["blocks", "refresh", "--root", root, "--source", outsideURL.path, "--apply"])
        XCTAssertNotEqual(result.status, 0, "an absolute outside source must be rejected: \(result.output)")
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), before,
                       "the file outside the workspace must be untouched")
    }

    func testBlocksRefreshToleratesDuplicateCacheRecords() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        try write("Intro\n/daymark open-loops\nOutro\n", relativePath: sourcePath, root: root)
        try write("""
        {
          "version" : 1,
          "records" : [
            { "commandHash" : "dup", "rawCommand" : "/daymark open-loops", "refreshedAt" : "1970-01-01T00:00:00Z", "renderedOutputHash" : "h1", "rendererName" : "open-loops", "sourcePath" : "daily/2026/06/2026-06-29.md" },
            { "commandHash" : "dup", "rawCommand" : "/daymark open-loops", "refreshedAt" : "1970-01-01T00:01:00Z", "renderedOutputHash" : "h2", "rendererName" : "open-loops", "sourcePath" : "daily/2026/06/2026-06-29.md" }
          ]
        }
        """, relativePath: ".daymark/dynamic-blocks.json", root: root)

        let result = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--date", "2026-06-29", "--apply"])
        XCTAssertEqual(result.status, 0, "a duplicate-key cache must not crash apply: \(result.output)")
        let applied = try read(sourcePath, root: root)
        XCTAssertTrue(applied.contains("daymark:block-begin"), "the note is written despite the corrupt cache")
    }

    func testBlocksRequiresSubcommand() throws {
        try skipIfBinaryMissing()
        let result = try runDaymark(["blocks", "--root", tempRoot()])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("blocks subcommand is required"), result.output)
    }

    func testBlocksRefreshRequiresSource() throws {
        try skipIfBinaryMissing()
        let result = try runDaymark(["blocks", "refresh", "--root", tempRoot()])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("--source is required"), result.output)
    }

    func testBlocksRefreshReportsMissingSource() throws {
        try skipIfBinaryMissing()
        let result = try runDaymark(["blocks", "refresh", "--root", tempRoot(), "--source", "daily/missing.md"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("source not found"), result.output)
    }

    func testBlocksRefreshRejectsUnknownFlag() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try write("/daymark open-loops\n", relativePath: "daily/x.md", root: root)
        let result = try runDaymark(["blocks", "refresh", "--root", root, "--source", "daily/x.md", "--bogus"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("unknown blocks flag: --bogus"), result.output)
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

    func testBlocksRefreshSourceListDryRunApplyAndRepeatApplyAreIdempotent() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        try write("""
        # Today

        Intro stays.
        /daymark source-list #project/daymark
        Outro stays.
        """, relativePath: sourcePath, root: root)
        try write("""
        # Daymark Project

        Build local dynamic blocks. #project/daymark
        """, relativePath: "projects/daymark.md", root: root)
        try write("""
        # Generated Only

        <!-- daymark:block-begin abc -->
        Generated #project/daymark
        <!-- daymark:block-end abc -->
        """, relativePath: "projects/generated.md", root: root)

        let original = try read(sourcePath, root: root)
        let dryRun = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath])
        XCTAssertEqual(dryRun.status, 0, dryRun.output)
        XCTAssertTrue(dryRun.output.contains("### Source List: #project/daymark"), dryRun.output)
        XCTAssertTrue(dryRun.output.contains("- Daymark Project (`projects/daymark.md`)"), dryRun.output)
        XCTAssertFalse(dryRun.output.contains("Generated Only"), dryRun.output)
        XCTAssertEqual(try read(sourcePath, root: root), original)
        let cachePath = "\(root)/.daymark/dynamic-blocks.json"
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachePath))

        let apply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--apply"])
        XCTAssertEqual(apply.status, 0, apply.output)
        let applied = try read(sourcePath, root: root)
        XCTAssertTrue(applied.contains("Intro stays."))
        XCTAssertTrue(applied.contains("/daymark source-list #project/daymark"))
        XCTAssertTrue(applied.contains("- Daymark Project (`projects/daymark.md`)"))
        XCTAssertTrue(applied.contains("Outro stays."))
        XCTAssertEqual(applied.components(separatedBy: "daymark:block-begin").count - 1, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath))
        let cache = try String(contentsOfFile: cachePath, encoding: .utf8)
        XCTAssertTrue(cache.contains("\"rendererName\" : \"source-list\""), cache)

        let repeatApply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--apply"])
        XCTAssertEqual(repeatApply.status, 0, repeatApply.output)
        XCTAssertEqual(try read(sourcePath, root: root), applied)
    }

    func testBlocksRefreshCodexContextDryRunApplyAndRepeatApplyAreIdempotent() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let sourcePath = "daily/2026/06/2026-06-29.md"
        try write("""
        # Today

        Intro stays.
        /daymark codex-context #project/daymark
        Outro stays.
        """, relativePath: sourcePath, root: root)
        try write("""
        # Daymark Project

        Build local Codex handoff views. #project/daymark
        """, relativePath: "projects/daymark.md", root: root)
        try write("""
        # Ship beta handoff

        ## Source

        Path: `projects/daymark.md`
        """, relativePath: "specs/tasks/2026-06-29-ship-beta.md", root: root)
        try write("""
        # Context Bundle: Ship beta handoff

        ## Task

        Task: `specs/tasks/2026-06-29-ship-beta.md`
        """, relativePath: "artifacts/context-bundles/2026-06-29-ship-beta-context.md", root: root)
        try write("""
        # Generated Only

        <!-- daymark:block-begin abc -->
        #project/daymark
        <!-- daymark:block-end abc -->
        """, relativePath: "specs/tasks/2026-06-29-generated.md", root: root)

        let original = try read(sourcePath, root: root)
        let dryRun = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath])
        XCTAssertEqual(dryRun.status, 0, dryRun.output)
        XCTAssertTrue(dryRun.output.contains("### Codex Context: #project/daymark"), dryRun.output)
        XCTAssertTrue(dryRun.output.contains("- Ship beta handoff (`specs/tasks/2026-06-29-ship-beta.md`) source: `projects/daymark.md`"), dryRun.output)
        XCTAssertTrue(dryRun.output.contains("- Context Bundle: Ship beta handoff (`artifacts/context-bundles/2026-06-29-ship-beta-context.md`) task: `specs/tasks/2026-06-29-ship-beta.md`; source: `projects/daymark.md`"), dryRun.output)
        XCTAssertFalse(dryRun.output.contains("Generated Only"), dryRun.output)
        XCTAssertEqual(try read(sourcePath, root: root), original)
        let cachePath = "\(root)/.daymark/dynamic-blocks.json"
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachePath))

        let apply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--apply"])
        XCTAssertEqual(apply.status, 0, apply.output)
        let applied = try read(sourcePath, root: root)
        XCTAssertTrue(applied.contains("Intro stays."))
        XCTAssertTrue(applied.contains("/daymark codex-context #project/daymark"))
        XCTAssertTrue(applied.contains("### Codex Context: #project/daymark"))
        XCTAssertTrue(applied.contains("Outro stays."))
        XCTAssertEqual(applied.components(separatedBy: "daymark:block-begin").count - 1, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath))
        let cache = try String(contentsOfFile: cachePath, encoding: .utf8)
        XCTAssertTrue(cache.contains("\"rendererName\" : \"codex-context\""), cache)

        let repeatApply = try runDaymark(["blocks", "refresh", "--root", root, "--source", sourcePath, "--apply"])
        XCTAssertEqual(repeatApply.status, 0, repeatApply.output)
        XCTAssertEqual(try read(sourcePath, root: root), applied)
    }
}
