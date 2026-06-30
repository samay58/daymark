import XCTest
import DaymarkCore

/// Round-trip guards for the Codex handoff format: writer and parser live together in Core
/// and must agree even when the Source Excerpt contains headings or its own code fences.
final class CodexTaskRoundTripTests: XCTestCase {
    private func sampleDraft(excerpt: String, constraints: [String] = ["Keep it small"]) -> CodexTaskDraft {
        CodexTaskDraft(
            title: "Make the open loops view",
            goal: "Wire up the open loops list",
            sourcePath: "daily/2026/06/2026-06-29.md",
            sourceLine: 12,
            sourceEndLine: 18,
            sourceBlock: "Capture",
            sourceExcerpt: excerpt,
            constraints: constraints,
            suggestedFilePath: "specs/tasks/2026-06-29-make-the-open-loops-view.md",
            acceptanceCriteria: ["Loops render"]
        )
    }

    func testRoundTripPreservesExcerptWithHeadings() {
        let excerpt = """
        ## Capture
        - [ ] do the thing
        ### Notes
        more text
        """
        let draft = sampleDraft(excerpt: excerpt)
        let parsed = CodexTaskDraft.parse(taskMarkdown: draft.markdown(), taskRelativePath: draft.suggestedFilePath)
        XCTAssertEqual(parsed.sourceExcerpt, excerpt, "an excerpt with ## headings must round-trip verbatim")
        XCTAssertEqual(parsed.title, draft.title)
        XCTAssertEqual(parsed.goal, draft.goal)
        XCTAssertEqual(parsed.sourcePath, draft.sourcePath)
        XCTAssertEqual(parsed.sourceLine, 12)
        XCTAssertEqual(parsed.sourceEndLine, 18)
        XCTAssertEqual(parsed.sourceBlock, "Capture")
    }

    func testRoundTripPreservesExcerptWithNestedCodeFence() {
        let excerpt = """
        Here is code:
        ```swift
        let x = 1
        ```
        done
        """
        let draft = sampleDraft(excerpt: excerpt)
        let markdown = draft.markdown()
        XCTAssertTrue(markdown.contains("````md"), "an excerpt with a nested ``` needs a longer outer fence")
        let parsed = CodexTaskDraft.parse(taskMarkdown: markdown, taskRelativePath: draft.suggestedFilePath)
        XCTAssertEqual(parsed.sourceExcerpt, excerpt, "the nested code fence survives the round trip")
    }

    func testBacktickFreeExcerptStillUsesThreeBacktickFence() {
        let draft = sampleDraft(excerpt: "plain excerpt with no backticks")
        XCTAssertTrue(draft.markdown().contains("```md\n"), "no regression for ordinary excerpts")
        XCTAssertFalse(draft.markdown().contains("````"))
    }

    func testHeadingExcerptDoesNotHijackLaterSections() {
        let excerpt = """
        ## Constraints
        - this line is part of the excerpt, not the real Constraints section
        ## Acceptance Criteria
        - [ ] also part of the excerpt
        """
        let draft = sampleDraft(excerpt: excerpt, constraints: ["Real constraint one"])
        let parsed = CodexTaskDraft.parse(taskMarkdown: draft.markdown(), taskRelativePath: draft.suggestedFilePath)
        XCTAssertEqual(parsed.sourceExcerpt, excerpt)
        XCTAssertTrue(parsed.constraints.contains("Real constraint one"),
                      "the real Constraints section is parsed, not the in-excerpt copy")
        XCTAssertFalse(parsed.constraints.contains("this line is part of the excerpt, not the real Constraints section"))
    }

    func testChainToContextBundlePreservesExcerpt() {
        let excerpt = """
        ## Capture
        ```json
        {"k": 1}
        ```
        """
        let draft = sampleDraft(excerpt: excerpt)
        let parsed = CodexTaskDraft.parse(taskMarkdown: draft.markdown(), taskRelativePath: draft.suggestedFilePath)
        let bundle = CodexContextBundle.from(
            draft: parsed,
            taskRelativePath: draft.suggestedFilePath,
            date: Date(timeIntervalSince1970: 0),
            existingRelativePaths: []
        )
        XCTAssertEqual(bundle.sourceExcerpt, excerpt.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // ASB-3: the writability predicate is the single source of truth shared with validate().
    func testIsWritablePredicateMatchesWriterValidate() {
        let writable = sampleDraft(excerpt: "has content")
        XCTAssertTrue(writable.isWritable)
        XCTAssertNoThrow(try CodexTaskFileWriter().validate(writable))

        var blank = writable
        blank.goal = "  "
        XCTAssertFalse(blank.isWritable)
        XCTAssertThrowsError(try CodexTaskFileWriter().validate(blank))

        var badPath = writable
        badPath.suggestedFilePath = "notes/foo.md"
        XCTAssertFalse(badPath.isWritable)
        XCTAssertThrowsError(try CodexTaskFileWriter().validate(badPath))
    }
}
