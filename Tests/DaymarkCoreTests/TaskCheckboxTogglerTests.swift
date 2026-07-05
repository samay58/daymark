import XCTest
@testable import DaymarkCore

final class TaskCheckboxTogglerTests: XCTestCase {
    func testOpenToDone() {
        let markdown = "- [ ] wash the car"
        let caret = 5
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: caret) else {
            return XCTFail("expected an edit")
        }
        XCTAssertEqual(edit.replacement, "x")
        XCTAssertEqual((markdown as NSString).substring(with: edit.range), " ")

        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "- [x] wash the car")
    }

    func testDoneToOpen() {
        let markdown = "- [x] wash the car"
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 5) else {
            return XCTFail("expected an edit")
        }
        XCTAssertEqual(edit.replacement, " ")

        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "- [ ] wash the car")
    }

    func testIndentationPreserved() {
        let markdown = "    - [ ] nested task"
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 9) else {
            return XCTFail("expected an edit")
        }
        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "    - [x] nested task")
    }

    func testMetadataPreserved() {
        let markdown = "- [ ] ping Sarah #launch @sarah due:today"
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 3) else {
            return XCTFail("expected an edit")
        }
        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "- [x] ping Sarah #launch @sarah due:today")
    }

    func testNonTaskLineReturnsNil() {
        let markdown = "just a plain paragraph"
        XCTAssertNil(TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 3))
    }

    func testInsideWellFormedRegionReturnsNil() {
        let markdown = """
        /daymark open-loops
        <!-- daymark:block-begin abc123 -->
        - [ ] generated checklist item
        <!-- daymark:block-end abc123 -->
        """
        let nsMarkdown = markdown as NSString
        let taskLineLocation = nsMarkdown.range(of: "- [ ] generated checklist item").location
        XCTAssertNil(TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: taskLineLocation + 3))
    }

    func testInsideFenceReturnsNil() {
        let markdown = """
        ```
        - [ ] fenced task
        ```
        """
        let nsMarkdown = markdown as NSString
        let taskLineLocation = nsMarkdown.range(of: "- [ ] fenced task").location
        XCTAssertNil(TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: taskLineLocation + 3))
    }

    func testCRLFDocument() {
        let markdown = "- [ ] first\r\n- [x] second\r\n"
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 3) else {
            return XCTFail("expected an edit")
        }
        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "- [x] first\r\n- [x] second\r\n")
    }

    func testEmojiHeavyLine() {
        let markdown = "- [ ] 🔥🔥 celebrate 🎉 launch"
        guard let edit = TaskCheckboxToggler.toggleEdit(in: markdown, atLineContaining: 3) else {
            return XCTFail("expected an edit")
        }
        let nsMarkdown = NSMutableString(string: markdown)
        nsMarkdown.replaceCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(nsMarkdown as String, "- [x] 🔥🔥 celebrate 🎉 launch")
    }
}
