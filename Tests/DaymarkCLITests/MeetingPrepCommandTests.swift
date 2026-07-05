import XCTest

final class MeetingPrepCommandTests: XCTestCase {
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
        let dir = "\(NSTemporaryDirectory())daymark-meeting-prep-cli-\(UUID().uuidString)"
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

    func testMeetingPrepDryRunPrintsPreviewAndWritesNothing() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let event = try writeEventJSON(outsideRootNamed: "event-\(UUID().uuidString).json")
        let project = """
        # Acme Project

        Renewal notes. #deal/acme
        What changed in procurement?
        """
        try write(project, relativePath: "projects/acme.md", root: root)
        try write("""
        # Daily

        - [ ] Send renewal model #deal/acme
        - [x] Completed old note #deal/acme
        """, relativePath: "daily/2026/06/2026-06-30.md", root: root)

        let result = try runDaymark(["meeting-prep", "--root", root, "--event-file", event.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Target: meetings/2026-07-01-acme-partner-sync.md"), result.output)
        XCTAssertTrue(result.output.contains("# Meeting Prep: Acme Partner Sync"), result.output)
        XCTAssertTrue(result.output.contains("- Source: Acme Project (`projects/acme.md`)"), result.output)
        XCTAssertTrue(result.output.contains("- [ ] Send renewal model #deal/acme (`daily/2026/06/2026-06-30.md:3`)"), result.output)
        XCTAssertTrue(result.output.contains("- What changed in procurement? (`projects/acme.md:4`)"), result.output)
        XCTAssertFalse(result.output.contains("Completed old note"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(root)/meetings"))
        XCTAssertEqual(try read("projects/acme.md", root: root), project)
    }

    func testMeetingPrepApplyWritesOneFileAndRepeatApplySuffixes() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let event = try writeEventJSON(outsideRootNamed: "event-\(UUID().uuidString).json")
        let source = "# Acme Project\n\n#deal/acme\n"
        try write(source, relativePath: "projects/acme.md", root: root)

        let first = try runDaymark(["meeting-prep", "--root", root, "--event-file", event.path, "--apply"])
        let second = try runDaymark(["meeting-prep", "--root", root, "--event-file", event.path, "--apply"])

        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(first.output.contains("Created: meetings/2026-07-01-acme-partner-sync.md"), first.output)
        XCTAssertTrue(second.output.contains("Created: meetings/2026-07-01-acme-partner-sync-2.md"), second.output)
        let firstMarkdown = try read("meetings/2026-07-01-acme-partner-sync.md", root: root)
        let secondMarkdown = try read("meetings/2026-07-01-acme-partner-sync-2.md", root: root)
        XCTAssertTrue(firstMarkdown.contains("Source event: `\(event.path)`"))
        XCTAssertTrue(secondMarkdown.contains("Prep File\n\n`meetings/2026-07-01-acme-partner-sync-2.md`"))
        XCTAssertEqual(try read("projects/acme.md", root: root), source)
    }

    func testMeetingPrepInvalidEventFileFailsClearly() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let event = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bad-event-\(UUID().uuidString).json")
        try #"{"title":"Acme","startsAt":"soon","endsAt":"2026-07-01T15:00:00Z"}"#
            .write(to: event, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: event) }

        let result = try runDaymark(["meeting-prep", "--root", root, "--event-file", event.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("invalid meeting event date: soon"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(root)/meetings"))
    }

    func testMeetingPrepEmptyContextStillProducesReadablePrep() throws {
        try skipIfBinaryMissing()
        let root = tempRoot()
        let event = try writeEventJSON(outsideRootNamed: "event-\(UUID().uuidString).json")

        let result = try runDaymark(["meeting-prep", "--root", root, "--event-file", event.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("No local context found for #deal/acme."), result.output)
        XCTAssertTrue(result.output.contains("No open loops found."), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(root)/meetings"))
    }

    private func writeEventJSON(outsideRootNamed name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try """
        {
          "title": "Acme Partner Sync",
          "startsAt": "2026-07-01T14:30:00Z",
          "endsAt": "2026-07-01T15:00:00Z",
          "attendees": ["Sarah Chen", "Maya Lee"],
          "location": "Zoom",
          "tags": ["#deal/acme"],
          "notes": "Discuss renewal questions."
        }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
