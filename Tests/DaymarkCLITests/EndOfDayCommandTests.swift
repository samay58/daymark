import XCTest

final class EndOfDayCommandTests: XCTestCase {
    private var binaryURL: URL? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildDirectory = repoRoot.appendingPathComponent(".build", isDirectory: true)
        for relativePath in ["arm64-apple-macosx/debug/daymark", "debug/daymark"] {
            let candidate = buildDirectory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func skipIfBinaryMissing() throws {
        try XCTSkipIf(binaryURL == nil, "daymark binary not built; run `swift build --product daymark` before this test")
    }

    private func tempRoot() -> String {
        let dir = "\(NSTemporaryDirectory())daymark-eod-cli-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
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

    func testEndOfDayListsOnlyTodaysOpenTasks() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let url = URL(fileURLWithPath: "\(root)/daily/2026/06/2026-06-28.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        # Today

        ## Capture

        - [ ] review memo before close
        - [x] send update
        """.write(to: url, atomically: true, encoding: .utf8)

        let result = try runDaymark(["end-of-day", "--date", "2026-06-28", "--root", root])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Still open for 2026-06-28"), result.output)
        XCTAssertTrue(result.output.contains("review memo before close"), result.output)
        XCTAssertFalse(result.output.contains("send update"), result.output)
    }

    func testEndOfDayInvalidDateUsesNeutralDateError() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()

        let result = try runDaymark(["end-of-day", "--date", "not-a-date", "--root", root])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("invalid date: not-a-date"), result.output)
        XCTAssertFalse(result.output.contains("invalid rollover date"), result.output)
    }
}
