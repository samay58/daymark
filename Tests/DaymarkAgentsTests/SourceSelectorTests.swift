import XCTest
@testable import DaymarkAgents

final class SourceSelectorTests: XCTestCase {
    func testSelectedTextWinsOverCurrentBlock() throws {
        let text = """
        # Today

        First paragraph.

        Second paragraph.
        """
        let range = nsRange(of: "First paragraph.", in: text)

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: range,
            cursorLocation: range.location,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "First paragraph.")
        XCTAssertEqual(selection.sourcePath, "daily/2026/06/2026-06-29.md")
        XCTAssertEqual(selection.startLine, 3)
    }

    func testNoSelectionUsesCurrentParagraph() throws {
        let text = """
        # Today

        First paragraph spans
        two lines.

        Second paragraph.
        """
        let cursor = nsRange(of: "two lines", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "First paragraph spans\ntwo lines.")
        XCTAssertEqual(selection.startLine, 3)
        XCTAssertEqual(selection.endLine, 4)
    }

    func testNoSelectionUsesCurrentListItemWithContinuation() throws {
        let text = """
        ## Capture

        - [ ] Build Codex task composer
          with a readable preview.
        - [ ] Another task.
        """
        let cursor = nsRange(of: "readable preview", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "- [ ] Build Codex task composer\n  with a readable preview.")
        XCTAssertEqual(selection.startLine, 3)
        XCTAssertEqual(selection.endLine, 4)
        XCTAssertEqual(selection.heading, "Capture")
    }

    func testHeadingBoundaryDoesNotSelectNextSection() throws {
        let text = """
        ## Brief

        Use this text.

        ## Capture

        Do not include this.
        """
        let cursor = nsRange(of: "Use this", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "Use this text.")
        XCTAssertEqual(selection.heading, "Brief")
    }

    func testCursorOnHeadingUsesFirstContentBlockInSection() throws {
        let text = """
        ## Capture

        Use this text.

        Do not include this paragraph.
        """
        let cursor = nsRange(of: "## Capture", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "Use this text.")
        XCTAssertEqual(selection.startLine, 3)
        XCTAssertEqual(selection.endLine, 3)
        XCTAssertEqual(selection.heading, "Capture")
    }

    func testCursorOnEmptyHeadingSectionIsRejected() {
        let text = """
        ## Brief

        ## Capture

        ## End of day
        """
        let cursor = nsRange(of: "## End of day", in: text).location

        XCTAssertThrowsError(
            try SourceSelector().select(
                text: text,
                selectedRange: NSRange(location: cursor, length: 0),
                cursorLocation: cursor,
                sourcePath: "daily/2026/06/2026-06-29.md"
            )
        ) { error in
            XCTAssertEqual(error as? SourceSelector.Error, .emptySource)
        }
    }

    func testFencedCodeBlockStaysTogether() throws {
        let text = """
        ## Notes

        ```swift
        let value = 1
        ```

        After.
        """
        let cursor = nsRange(of: "value", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "```swift\nlet value = 1\n```")
        XCTAssertEqual(selection.startLine, 3)
        XCTAssertEqual(selection.endLine, 5)
    }

    func testCursorAtBlankLineUsesNextNonBlankBlock() throws {
        let text = """
        # Today

        First block.

        Next block.
        """
        let cursor = nsRange(of: "\n\nNext", in: text).location + 1

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "Next block.")
        XCTAssertEqual(selection.startLine, 5)
    }

    func testCRLFInputTracksLineNumbers() throws {
        let text = "# Today\r\n\r\nFirst block.\r\n\r\nSecond block.\r\n"
        let cursor = nsRange(of: "Second", in: text).location

        let selection = try SourceSelector().select(
            text: text,
            selectedRange: NSRange(location: cursor, length: 0),
            cursorLocation: cursor,
            sourcePath: "daily/2026/06/2026-06-29.md"
        )

        XCTAssertEqual(selection.excerpt, "Second block.")
        XCTAssertEqual(selection.startLine, 5)
    }

    func testBlankSourceIsRejected() {
        XCTAssertThrowsError(
            try SourceSelector().select(
                text: "   ",
                selectedRange: NSRange(location: 0, length: 0),
                cursorLocation: 0,
                sourcePath: "daily/2026/06/2026-06-29.md"
            )
        )
    }

    private func nsRange(of needle: String, in text: String) -> NSRange {
        let range = (text as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound)
        return range
    }
}
