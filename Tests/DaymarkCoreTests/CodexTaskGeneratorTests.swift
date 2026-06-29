import XCTest
@testable import DaymarkCore

final class CodexTaskGeneratorTests: XCTestCase {
    func testDraftMarkdownIncludesSourceContextAndCriteria() {
        let draft = CodexTaskDraft(
            title: "Make rollover deterministic",
            goal: "Prevent duplicate rolled-over tasks.",
            sourcePath: "daily/2026/06/2026-06-28.md",
            sourceLine: 12,
            sourceExcerpt: "- [ ] Prevent duplicate rolled-over tasks.",
            constraints: ["Do not modify the source note"],
            suggestedFilePath: "specs/tasks/2026-06-29-make-rollover-deterministic.md",
            acceptanceCriteria: ["Duplicate rollovers are prevented"]
        )

        let markdown = draft.markdown()

        XCTAssertTrue(markdown.contains("# Make rollover deterministic"))
        XCTAssertTrue(markdown.contains("Prevent duplicate rolled-over tasks."))
        XCTAssertTrue(markdown.contains("daily/2026/06/2026-06-28.md"))
        XCTAssertTrue(markdown.contains("Line: 12"))
        XCTAssertTrue(markdown.contains("- Do not modify the source note"))
        XCTAssertTrue(markdown.contains("- [ ] Duplicate rollovers are prevented"))
        XCTAssertTrue(markdown.contains("- [ ] Source note remains unchanged"))
        XCTAssertTrue(markdown.contains("- [ ] Task file is readable Markdown"))
        XCTAssertTrue(markdown.contains("```md\n- [ ] Prevent duplicate rolled-over tasks.\n```"))
        XCTAssertFalse(markdown.contains("Optional"))
        XCTAssertFalse(markdown.contains("TBD"))
    }

    func testBlankDraftIsRejectedBeforeWriting() throws {
        let draft = CodexTaskDraft(
            title: "   ",
            goal: "  ",
            sourcePath: "daily/2026/06/2026-06-28.md",
            sourceExcerpt: "  ",
            suggestedFilePath: "specs/tasks/2026-06-29-empty.md",
            acceptanceCriteria: []
        )

        XCTAssertThrowsError(try CodexTaskFileWriter().validate(draft)) { error in
            XCTAssertEqual(error as? CodexTaskFileWriter.Error, .blankDraft)
        }
    }

    func testTaskFileWriterCreatesCollisionSafeMarkdownFiles() throws {
        let root = WorkspaceRoot(path: "\(NSTemporaryDirectory())daymark-codex-writer-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.expandedPath) }
        let writer = CodexTaskFileWriter()
        let draft = CodexTaskDraft(
            title: "Make rollover deterministic",
            goal: "Prevent duplicate rolled-over tasks.",
            sourcePath: "daily/2026/06/2026-06-28.md",
            sourceLine: 12,
            sourceExcerpt: "- [ ] Prevent duplicate rolled-over tasks.",
            constraints: ["Do not modify the source note"],
            suggestedFilePath: "specs/tasks/2026-06-29-make-rollover-deterministic.md",
            acceptanceCriteria: ["Duplicate rollovers are prevented"]
        )

        let first = try writer.write(draft, root: root)
        let second = try writer.write(draft, root: root)

        XCTAssertEqual(first.relativePath, "specs/tasks/2026-06-29-make-rollover-deterministic.md")
        XCTAssertEqual(second.relativePath, "specs/tasks/2026-06-29-make-rollover-deterministic-2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.expandedURL.appendingPathComponent(first.relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.expandedURL.appendingPathComponent(second.relativePath).path))
        XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), draft.markdown())
    }

    func testTaskFileWriterDoesNotModifySourceNote() throws {
        let root = WorkspaceRoot(path: "\(NSTemporaryDirectory())daymark-codex-source-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.expandedPath) }
        let source = root.expandedURL.appendingPathComponent("daily/2026/06/2026-06-28.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep me".write(to: source, atomically: true, encoding: .utf8)
        let draft = CodexTaskDraft(
            title: "Keep source safe",
            goal: "Write a task without editing the note.",
            sourcePath: "daily/2026/06/2026-06-28.md",
            sourceExcerpt: "keep me",
            suggestedFilePath: "specs/tasks/2026-06-29-keep-source-safe.md",
            acceptanceCriteria: ["Source note is unchanged"]
        )

        _ = try CodexTaskFileWriter().write(draft, root: root)

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "keep me")
    }

    func testSuggestedPathUsesSpecsTasksAndSlug() {
        let path = CodexTaskDraft.suggestedRelativePath(
            title: "Fix: Rollover / duplicate write!",
            date: fixedDate()
        )

        XCTAssertEqual(path, "specs/tasks/2026-06-29-fix-rollover-duplicate-write.md")
    }

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 29
        components.hour = 12
        return components.date!
    }
}
