import XCTest

final class CodexTaskCommandTests: XCTestCase {
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
        try XCTSkipIf(binaryURL == nil, "daymark binary not built; run `swift build --product daymark` first")
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-codex-cli-\(UUID().uuidString)"
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

    func testCodexTaskDryRunPrintsPreviewAndWritesNothing() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Today

        ## Capture

        Build selected text to Codex task handoff.
        Keep source note unchanged.
        """, named: "2026-06-29.md", in: root)

        let result = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--line", "5",
            "--date", "2026-06-29"
        ])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Target: specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"), result.output)
        XCTAssertTrue(result.output.contains("# Build selected text to Codex task handoff"), result.output)
        XCTAssertTrue(result.output.contains("Path: `daily/2026/06/2026-06-29.md`"), result.output)
        XCTAssertTrue(result.output.contains("Build selected text to Codex task handoff."), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(root)/specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"))
    }

    func testCodexTaskApplyWritesOneFileAndLeavesSourceUnchanged() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let sourceMarkdown = """
        # Today

        ## Capture

        Build selected text to Codex task handoff.
        Keep source note unchanged.
        """
        try writeDaily(sourceMarkdown, named: "2026-06-29.md", in: root)

        let result = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--line", "5",
            "--date", "2026-06-29",
            "--apply"
        ])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Created: specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"), result.output)
        let file = "\(root)/specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"
        let markdown = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Build selected text to Codex task handoff"))
        XCTAssertEqual(try String(contentsOfFile: "\(root)/daily/2026/06/2026-06-29.md", encoding: .utf8), sourceMarkdown)
    }

    func testCodexTaskApplyDoesNotOverwriteExistingTaskFile() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Today

        ## Capture

        Build selected text to Codex task handoff.
        Keep source note unchanged.
        """, named: "2026-06-29.md", in: root)

        _ = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--line", "5",
            "--date", "2026-06-29",
            "--apply"
        ])
        let second = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--line", "5",
            "--date", "2026-06-29",
            "--apply"
        ])

        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("Created: specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff-2.md"), second.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(root)/specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(root)/specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff-2.md"))
    }

    func testCodexTaskCanUseExplicitSelectionFile() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let selectionFile = "\(root)/selection.txt"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try "Tighten the preview before writing.".write(toFile: selectionFile, atomically: true, encoding: .utf8)
        try writeDaily("# Today\n\n## Capture\n\nIgnored block.\n", named: "2026-06-29.md", in: root)

        let result = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--selection-file", selectionFile,
            "--date", "2026-06-29"
        ])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("# Tighten the preview before writing"), result.output)
        XCTAssertFalse(result.output.contains("# Ignored block"), result.output)
    }

    func testCodexTaskRejectsLineBeyondSourceFile() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        try writeDaily("""
        # Today

        ## Capture

        Build selected text to Codex task handoff.
        """, named: "2026-06-29.md", in: root)

        let result = try runDaymark([
            "codex-task",
            "--root", root,
            "--source", "daily/2026/06/2026-06-29.md",
            "--line", "99",
            "--date", "2026-06-29"
        ])

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("invalid line: 99"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(root)/specs/tasks"))
    }
}
