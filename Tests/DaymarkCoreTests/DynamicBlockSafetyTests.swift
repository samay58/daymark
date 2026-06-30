import XCTest
import DaymarkCore

/// Hardening cases for the Dynamic Blocks slice: malformed/unterminated regions, CRLF
/// preservation, fence-type matching, hash-aware region bounds, and duplicate-safe cache.
final class DynamicBlockSafetyTests: XCTestCase {
    private func makeRoot() -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-dyn-safety-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return WorkspaceRoot(path: path)
    }

    // MARK: - DBS-2: unterminated generated region must not hide following tasks

    func testUnterminatedRegionPreservesFollowingTasks() {
        let markdown = """
        - [ ] real task
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        - [ ] generated task
        - [ ] another real task after a missing end marker
        """

        let stripped = DynamicBlockRegion.removingGeneratedRegions(from: markdown)

        XCTAssertTrue(stripped.contains("- [ ] real task"))
        XCTAssertTrue(stripped.contains("another real task after a missing end marker"),
                      "an unterminated begin marker must not drop following lines")
        // The begin line itself is preserved verbatim when there is no matching end.
        XCTAssertTrue(stripped.contains("<!-- daymark:block-begin abc123 -->"))
    }

    func testWellFormedRegionIsStillStripped() {
        let markdown = """
        - [ ] keep me
        <!-- daymark:block-begin abc123 -->
        - [ ] generated
        <!-- daymark:block-end abc123 -->
        - [ ] keep me too
        """
        let stripped = DynamicBlockRegion.removingGeneratedRegions(from: markdown)
        XCTAssertFalse(stripped.contains("- [ ] generated"))
        XCTAssertTrue(stripped.contains("- [ ] keep me"))
        XCTAssertTrue(stripped.contains("- [ ] keep me too"))
    }

    // MARK: - DBS-4: apply preserves the file's dominant line endings

    func testApplyPreservesCRLFLineEndings() throws {
        let markdown = "Intro\r\n/daymark open-loops\r\nOutro\r\n"
        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "follow up", status: .open, notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        let applied = try plan.apply(to: markdown)

        XCTAssertTrue(applied.contains("\r\n"), "CRLF notes must stay CRLF")
        XCTAssertFalse(applied.contains("\n\n") && !applied.contains("\r\n\r\n"),
                       "no bare LF should be introduced into a CRLF file")
        // Every newline is a CRLF: stripping \r\n leaves no stray \n.
        XCTAssertFalse(applied.replacingOccurrences(of: "\r\n", with: "").contains("\n"),
                       "no bare LF outside or inside the generated region")
        XCTAssertTrue(applied.contains("Intro"))
        XCTAssertTrue(applied.contains("Outro"))
    }

    func testApplyKeepsLFNotesAsLF() throws {
        let markdown = "Intro\n/daymark open-loops\nOutro\n"
        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "follow up", status: .open, notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        let applied = try plan.apply(to: markdown)
        XCTAssertFalse(applied.contains("\r\n"), "LF notes must not gain CRLF")
    }

    // MARK: - DBS-5: fence matching respects marker type and length

    func testCommandInsideMixedFenceIsIgnored() throws {
        // A backtick-opened fence containing a tilde line must stay open; the /daymark line
        // inside it must not be parsed as a live command.
        let markdown = """
        ```
        ~~~
        /daymark open-loops
        ```
        /daymark open-loops
        """
        let commands = try DynamicBlockParser().parse(markdown: markdown, sourcePath: "daily/today.md")
        XCTAssertEqual(commands.count, 1, "only the command outside the fence is parsed")
        XCTAssertEqual(commands[0].lineNumber, 5)
    }

    func testLongerFenceIsNotClosedByShorterRun() throws {
        let markdown = """
        ````
        ```
        /daymark open-loops
        ````
        /daymark open-loops
        """
        let commands = try DynamicBlockParser().parse(markdown: markdown, sourcePath: "daily/today.md")
        XCTAssertEqual(commands.count, 1, "a 3-backtick line must not close a 4-backtick fence")
        XCTAssertEqual(commands[0].lineNumber, 5)
    }

    // MARK: - DBS-6: region close is bound by the existing begin marker's hash

    func testPlanReplacesOnlyTheMatchingHashRegion() throws {
        // A begin/end pair (hashA) followed by a foreign end marker (hashB). The planner must
        // replace only the hashA region, not consume up to the hashB end marker.
        let markdown = """
        /daymark open-loops
        <!-- daymark:block-begin aaaa -->
        stale
        <!-- daymark:block-end aaaa -->
        keep this line
        <!-- daymark:block-end bbbb -->
        """
        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "fresh", status: .open, notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        let applied = try plan.apply(to: markdown)
        XCTAssertFalse(applied.contains("stale"))
        XCTAssertTrue(applied.contains("keep this line"), "the foreign end marker region must be untouched")
        XCTAssertTrue(applied.contains("<!-- daymark:block-end bbbb -->"))
        XCTAssertTrue(applied.contains("fresh"))
    }

    func testPlanThrowsWhenBeginMarkerHasNoMatchingEnd() throws {
        let markdown = """
        /daymark open-loops
        <!-- daymark:block-begin aaaa -->
        stale with no matching end
        """
        XCTAssertThrowsError(try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: [],
            referenceDate: Date(timeIntervalSince1970: 0)
        )) { error in
            guard case DynamicBlockError.missingGeneratedRegionEnd = error else {
                return XCTFail("expected missingGeneratedRegionEnd, got \(error)")
            }
        }
    }

    func testEditedCommandStillBoundsExistingRegionByItsOwnHash() throws {
        // The existing region carries an old hash that no longer matches the current command's
        // hash. The planner must still find and replace it by the begin marker's own hash.
        let markdown = """
        /daymark open-loops #deal/acme
        <!-- daymark:block-begin oldhash99 -->
        stale output
        <!-- daymark:block-end oldhash99 -->
        """
        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: markdown,
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "acme task", status: .open, tags: ["#deal/acme"], notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(plan.patches.first?.operation, .replacement)
        let applied = try plan.apply(to: markdown)
        XCTAssertFalse(applied.contains("stale output"))
        XCTAssertEqual(applied.components(separatedBy: "daymark:block-begin").count - 1, 1,
                       "the existing region is replaced in place, not duplicated")
    }

    // MARK: - DBS-3: duplicate cache records collapse instead of trapping

    func testRecordToleratesDuplicateCacheRecords() throws {
        let root = makeRoot()
        let cacheURL = root.expandedURL
            .appendingPathComponent(".daymark", isDirectory: true)
            .appendingPathComponent("dynamic-blocks.json")
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Two records sharing sourcePath + commandHash would trap Dictionary(uniqueKeysWithValues:).
        let duplicate = """
        {
          "version" : 1,
          "records" : [
            { "commandHash" : "dup", "rawCommand" : "/daymark open-loops", "refreshedAt" : "1970-01-01T00:00:00Z", "renderedOutputHash" : "h1", "rendererName" : "open-loops", "sourcePath" : "daily/today.md" },
            { "commandHash" : "dup", "rawCommand" : "/daymark open-loops", "refreshedAt" : "1970-01-01T00:01:00Z", "renderedOutputHash" : "h2", "rendererName" : "open-loops", "sourcePath" : "daily/today.md" }
          ]
        }
        """
        try duplicate.write(to: cacheURL, atomically: true, encoding: .utf8)

        let plan = try DynamicBlockPatchPlanner().plan(
            markdown: "/daymark open-loops\n",
            sourcePath: "daily/today.md",
            tasks: [TaskItem(title: "fresh", status: .open, notePath: "daily/a.md", lineNumber: 1)],
            referenceDate: Date(timeIntervalSince1970: 0)
        )
        // Reaching past this call proves it did not trap on the duplicate keys.
        try DynamicBlockCacheStore().record(patches: plan.patches, root: root, refreshedAt: Date(timeIntervalSince1970: 120))

        let records = try DynamicBlockCacheStore().read(root: root)
        let dupRecords = records.filter { $0.commandHash == "dup" }
        XCTAssertEqual(dupRecords.count, 1, "duplicate (sourcePath, commandHash) records collapse to one")
        XCTAssertEqual(dupRecords.first?.renderedOutputHash, "h2", "last write wins on a duplicate key")
    }
}
