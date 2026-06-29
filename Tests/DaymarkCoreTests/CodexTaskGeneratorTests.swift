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

    func testEditedDraftCleansFieldsAndUpdatesMarkdown() {
        let draft = sampleDraft().withEditedFields(
            title: "  Tighten editable preview  ",
            goal: "  Let Samay revise the handoff before writing.  ",
            constraints: [" - [ ] Keep source read-only  ", " ", "* Write one file only"],
            acceptanceCriteria: [" - [ ] Edited title appears  ", "", "- Edited goal appears"],
            date: fixedDate(),
            existingRelativePaths: []
        )

        XCTAssertEqual(draft.title, "Tighten editable preview")
        XCTAssertEqual(draft.goal, "Let Samay revise the handoff before writing.")
        XCTAssertEqual(draft.constraints, ["Keep source read-only", "Write one file only"])
        XCTAssertEqual(draft.acceptanceCriteria, ["Edited title appears", "Edited goal appears"])
        XCTAssertEqual(draft.suggestedFilePath, "specs/tasks/2026-06-29-tighten-editable-preview.md")

        let markdown = draft.markdown()
        XCTAssertTrue(markdown.contains("# Tighten editable preview"))
        XCTAssertTrue(markdown.contains("- Keep source read-only"))
        XCTAssertTrue(markdown.contains("- [ ] Edited title appears"))
        XCTAssertFalse(markdown.contains("- [ ] - [ ]"))
    }

    func testEditedDraftRejectsBlankTitleAndGoalBeforeWriting() {
        let draft = sampleDraft().withEditedFields(
            title: " ",
            goal: "\n",
            constraints: [],
            acceptanceCriteria: ["Still has a criterion"],
            date: fixedDate(),
            existingRelativePaths: []
        )

        XCTAssertThrowsError(try CodexTaskFileWriter().validate(draft)) { error in
            XCTAssertEqual(error as? CodexTaskFileWriter.Error, .blankDraft)
        }
    }

    func testEditedTitleRefreshesSuggestedPathWithCollisionSuffix() {
        let draft = sampleDraft().withEditedFields(
            title: "Editable Preview",
            goal: "Keep the goal.",
            constraints: [],
            acceptanceCriteria: [],
            date: fixedDate(),
            existingRelativePaths: [
                "specs/tasks/2026-06-29-editable-preview.md",
                "specs/tasks/2026-06-29-editable-preview-2.md"
            ]
        )

        XCTAssertEqual(draft.suggestedFilePath, "specs/tasks/2026-06-29-editable-preview-3.md")
    }

    func testEditedCriteriaDeduplicatesDefaultAcceptanceCriteria() {
        let draft = sampleDraft().withEditedFields(
            title: "Editable Preview",
            goal: "Keep the goal.",
            constraints: [],
            acceptanceCriteria: [
                "Source note remains unchanged",
                "source note remains unchanged",
                "Task file is readable Markdown"
            ],
            date: fixedDate(),
            existingRelativePaths: []
        )

        let criteriaLines = draft.markdown()
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("- [ ] ") }

        XCTAssertEqual(criteriaLines.filter { $0 == "- [ ] Source note remains unchanged" }.count, 1)
        XCTAssertEqual(criteriaLines.filter { $0 == "- [ ] Task file is readable Markdown" }.count, 1)
    }

    func testContextBundleMarkdownIncludesTaskAndSourceProvenance() {
        let bundle = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: []
        )

        let markdown = bundle.markdown()

        XCTAssertTrue(markdown.contains("# Context Bundle: Original title"))
        XCTAssertTrue(markdown.contains("Task: `specs/tasks/2026-06-29-original-title.md`"))
        XCTAssertTrue(markdown.contains("Path: `daily/2026/06/2026-06-29.md`"))
        XCTAssertTrue(markdown.contains("Line: 8"))
        XCTAssertTrue(markdown.contains("```md\nMessy source note text.\n```"))
        XCTAssertTrue(markdown.contains("- [ ] Original criterion"))
        XCTAssertEqual(bundle.suggestedFilePath, "artifacts/context-bundles/2026-06-29-original-title-context.md")
    }

    func testContextBundlePreviewUsesCollisionSafeSuggestedPath() {
        let bundle = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: [
                "artifacts/context-bundles/2026-06-29-original-title-context.md",
                "artifacts/context-bundles/2026-06-29-original-title-context-2.md"
            ]
        )

        XCTAssertEqual(bundle.suggestedFilePath, "artifacts/context-bundles/2026-06-29-original-title-context-3.md")
        XCTAssertTrue(bundle.markdown().contains("`artifacts/context-bundles/2026-06-29-original-title-context-3.md`"))
    }

    func testContextBundleWriterCreatesCollisionSafeMarkdownAndLeavesInputsUnchanged() throws {
        let root = WorkspaceRoot(path: "\(NSTemporaryDirectory())daymark-context-bundle-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.expandedPath) }
        let source = root.expandedURL.appendingPathComponent("daily/2026/06/2026-06-29.md")
        let task = root.expandedURL.appendingPathComponent("specs/tasks/2026-06-29-original-title.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: task.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "source stays".write(to: source, atomically: true, encoding: .utf8)
        try "task stays".write(to: task, atomically: true, encoding: .utf8)
        let bundle = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: []
        )
        let writer = CodexContextBundleWriter()

        let first = try writer.write(bundle, root: root)
        let second = try writer.write(bundle, root: root)

        XCTAssertEqual(first.relativePath, "artifacts/context-bundles/2026-06-29-original-title-context.md")
        XCTAssertEqual(second.relativePath, "artifacts/context-bundles/2026-06-29-original-title-context-2.md")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source stays")
        XCTAssertEqual(try String(contentsOf: task, encoding: .utf8), "task stays")
        XCTAssertTrue(try String(contentsOf: first.url, encoding: .utf8).contains("Task: `specs/tasks/2026-06-29-original-title.md`"))
    }

    func testContextBundleWriterRechecksCollisionsAtApprovalTime() throws {
        let root = WorkspaceRoot(path: "\(NSTemporaryDirectory())daymark-context-bundle-race-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.expandedPath) }
        let preview = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: []
        )
        let existing = root.expandedURL.appendingPathComponent("artifacts/context-bundles/2026-06-29-original-title-context.md")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "already here".write(to: existing, atomically: true, encoding: .utf8)

        let result = try CodexContextBundleWriter().write(preview, root: root)

        XCTAssertEqual(result.relativePath, "artifacts/context-bundles/2026-06-29-original-title-context-2.md")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "already here")
        XCTAssertTrue(try String(contentsOf: result.url, encoding: .utf8).contains("Bundle File"))
    }

    func testContextBundleWriterRejectsBlankBundleAndInvalidPath() {
        var blank = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: []
        )
        blank.title = " "

        XCTAssertThrowsError(try CodexContextBundleWriter().validate(blank)) { error in
            XCTAssertEqual(error as? CodexContextBundleWriter.Error, .blankBundle)
        }

        var invalid = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "specs/tasks/2026-06-29-original-title.md",
            date: fixedDate(),
            existingRelativePaths: []
        )
        invalid.suggestedFilePath = "specs/tasks/not-a-bundle.md"

        XCTAssertThrowsError(try CodexContextBundleWriter().validate(invalid)) { error in
            XCTAssertEqual(error as? CodexContextBundleWriter.Error, .invalidPath)
        }

        var invalidTaskPath = CodexContextBundle.from(
            draft: sampleDraft(),
            taskRelativePath: "daily/2026/06/2026-06-29.md",
            date: fixedDate(),
            existingRelativePaths: []
        )
        invalidTaskPath.suggestedFilePath = "artifacts/context-bundles/2026-06-29-bundle.md"

        XCTAssertThrowsError(try CodexContextBundleWriter().validate(invalidTaskPath)) { error in
            XCTAssertEqual(error as? CodexContextBundleWriter.Error, .invalidPath)
        }
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

    private func sampleDraft() -> CodexTaskDraft {
        CodexTaskDraft(
            title: "Original title",
            goal: "Original goal.",
            sourcePath: "daily/2026/06/2026-06-29.md",
            sourceLine: 8,
            sourceExcerpt: "Messy source note text.",
            constraints: ["Do not modify the source note"],
            suggestedFilePath: "specs/tasks/2026-06-29-original-title.md",
            acceptanceCriteria: ["Original criterion"]
        )
    }
}
