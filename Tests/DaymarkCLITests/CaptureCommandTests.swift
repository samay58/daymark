import XCTest

/// End-to-end tests that run the built `daymark` binary against a temporary workspace.
/// They never touch the real `~/phoenix`. They are skipped when the product is not built;
/// run `swift build` before `swift test`.
final class CaptureCommandTests: XCTestCase {
    private var binaryURL: URL? {
        let fileManager = FileManager.default
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildDirectory = repoRoot.appendingPathComponent(".build", isDirectory: true)

        let candidatePaths = [
            "arm64-apple-macosx/debug/daymark",
            "debug/daymark",
            "Products/Debug/daymark",
            "arm64-apple-macosx/release/daymark",
            "release/daymark"
        ]

        for relativePath in candidatePaths {
            let candidate = buildDirectory.appendingPathComponent(relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let found = findBinary(daymarkIn: buildDirectory) {
            return found
        }

        return nil
    }

    private func findBinary(daymarkIn root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let file as URL in enumerator {
            guard file.lastPathComponent == "daymark" else { continue }
            let keys = try? file.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
            if keys?.isRegularFile == true {
                return file
            }
        }

        return nil
    }

    private func skipIfBinaryMissing() throws {
        try XCTSkipIf(
            binaryURL == nil,
            "daymark binary not built; run `swift build` before `swift test`"
        )
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-cli-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    @discardableResult
    private func runDaymark(
        _ arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval = 20
    ) throws -> (output: String, status: Int32) {
        let binaryURL = try XCTUnwrap(binaryURL, "daymark binary not found")
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        
        if let stdin {
            // Use a dedicated stdin pipe only when we need to provide captured input.
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        } else {
            // If we don't provide stdin explicitly, close stdin immediately so the command
            // does not wait on interactive input in non-tty test environments.
            let inPipe = Pipe()
            process.standardInput = inPipe
            inPipe.fileHandleForWriting.closeFile()
            try process.run()
        }

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

    private func contentsOfFirstMarkdown(in directory: String) throws -> String? {
        let url = URL(fileURLWithPath: directory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return nil
        }
        guard let markdown = files.first(where: { $0.pathExtension == "md" }) else { return nil }
        return try String(contentsOf: markdown, encoding: .utf8)
    }

    private func firstDailyNote(in root: String) throws -> String? {
        let dailyURL = URL(fileURLWithPath: root + "/daily")
        guard let enumerator = FileManager.default.enumerator(at: dailyURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    private func assertFailure(
        _ result: (output: String, status: Int32),
        expectedMessage: String,
        expectedUsage: String = "Usage: daymark capture"
    ) {
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains(expectedMessage), result.output)
        XCTAssertTrue(result.output.contains(expectedUsage), result.output)
    }

    func testCaptureWritesToMonthlySlipFile() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--root", root, "remember", "the", "milk"])
        XCTAssertEqual(result.status, 0, result.output)

        let contents = try contentsOfFirstMarkdown(in: root + "/slip")
        XCTAssertNotNil(contents, "a monthly slip file should be created")
        XCTAssertTrue(contents?.contains("remember the milk") == true, result.output)
    }

    func testCaptureAcceptsRootBeforeCommand() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["--root", root, "capture", "--", "--looks", "fine"])
        XCTAssertEqual(result.status, 0, result.output)

        let contents = try contentsOfFirstMarkdown(in: root + "/slip")
        XCTAssertTrue(contents?.contains("--looks fine") == true, result.output)
    }

    func testCaptureTodayAppendsUnderCaptureHeading() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--today", "--root", root, "a thought worth keeping"])
        XCTAssertEqual(result.status, 0, result.output)

        let daily = try firstDailyNote(in: root)
        XCTAssertNotNil(daily)
        XCTAssertTrue(daily?.contains("## Capture") == true)
        XCTAssertTrue(daily?.contains("a thought worth keeping") == true)
    }

    func testCaptureTaskWritesTaskLine() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--task", "--root", root, "file the report"])
        XCTAssertEqual(result.status, 0, result.output)

        let daily = try firstDailyNote(in: root)
        XCTAssertTrue(daily?.contains("- [ ] file the report") == true)
    }

    func testCaptureReadsFromStdinWhenNoText() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--root", root], stdin: "piped line one\npiped line two\n")
        XCTAssertEqual(result.status, 0, result.output)

        let contents = try contentsOfFirstMarkdown(in: root + "/slip")
        XCTAssertTrue(contents?.contains("piped line one") == true)
        XCTAssertTrue(contents?.contains("piped line two") == true)
    }

    func testCaptureWithNoTextFails() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--root", root])
        assertFailure(result, expectedMessage: "capture text is required")
    }

    func testCaptureWithUnknownFlagFails() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--root", root, "--bad-flag"])
        assertFailure(result, expectedMessage: "unknown flag: --bad-flag")
    }

    func testCaptureWithRootWithoutValueFails() throws {
        try skipIfBinaryMissing()
        let result = try runDaymark(["capture", "--root"])
        assertFailure(
            result,
            expectedMessage: "--root requires a value",
            expectedUsage: "Usage: daymark [--root <path>] <command>"
        )
    }

    func testCaptureTodayAndTaskConflictFails() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--today", "--task", "--root", root, "do not do both"])
        assertFailure(result, expectedMessage: "conflicting capture flags")
    }

    func testCaptureAllowsDashPrefixedTextAfterSentinel() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let result = try runDaymark(["capture", "--root", root, "--", "--urgent", "tomorrow"])
        XCTAssertEqual(result.status, 0, result.output)

        let contents = try contentsOfFirstMarkdown(in: root + "/slip")
        XCTAssertTrue(contents?.contains("--urgent tomorrow") == true, result.output)
    }
}
