import XCTest
@testable import DaymarkCore

final class CodexTaskGeneratorTests: XCTestCase {
    func testDraftMarkdownIncludesSourceAndCriteria() {
        let draft = CodexTaskDraft(
            title: "Make rollover deterministic",
            goal: "Prevent duplicate rolled-over tasks.",
            sourcePath: "daily/2026/06/2026-06-28.md",
            acceptanceCriteria: ["Duplicate rollovers are prevented"]
        )

        let markdown = draft.markdown()

        XCTAssertTrue(markdown.contains("daily/2026/06/2026-06-28.md"))
        XCTAssertTrue(markdown.contains("- [ ] Duplicate rollovers are prevented"))
    }
}
