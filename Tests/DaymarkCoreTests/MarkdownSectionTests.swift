import XCTest
@testable import DaymarkCore

final class MarkdownSectionTests: XCTestCase {
    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    func testAppendsUnderExistingHeadingBetweenSections() {
        let document = "# Today\n\n## Capture\n\n## Decisions\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)
        XCTAssertEqual(result, "# Today\n\n## Capture\n\n- x\n\n## Decisions\n")
    }

    func testAddsHeadingWhenAbsent() {
        let document = "# Today\n\nsome notes\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)
        XCTAssertEqual(result, "# Today\n\nsome notes\n\n## Capture\n\n- x\n")
    }

    func testAppendsWhenHeadingIsLastSection() {
        let document = "# Today\n\n## Capture\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)
        XCTAssertEqual(result, "# Today\n\n## Capture\n\n- x\n")
    }

    func testRepeatedAppendsDoNotDuplicateHeading() {
        let document = "# Today\n\n## Capture\n"
        let once = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)
        let twice = MarkdownSection.appendingEntry("- y", under: "## Capture", to: once)

        XCTAssertEqual(occurrences(of: "## Capture", in: twice), 1, "the heading must never be duplicated")
        let xIndex = try? XCTUnwrap(twice.range(of: "- x"))
        let yIndex = try? XCTUnwrap(twice.range(of: "- y"))
        XCTAssertNotNil(xIndex)
        XCTAssertNotNil(yIndex)
        if let xIndex, let yIndex {
            XCTAssertTrue(xIndex.lowerBound < yIndex.lowerBound, "entries keep insertion order")
        }
    }

    func testPreservesExistingContentInSection() {
        let document = "# Today\n\n## Capture\n\n- first\n\n## Decisions\n"
        let result = MarkdownSection.appendingEntry("- second", under: "## Capture", to: document)

        XCTAssertTrue(result.contains("- first"), "existing section content is preserved")
        XCTAssertTrue(result.contains("- second"), "new entry is added")
        XCTAssertTrue(result.contains("## Decisions"), "later sections are preserved")
        let firstRange = result.range(of: "- first")!
        let secondRange = result.range(of: "- second")!
        let decisionsRange = result.range(of: "## Decisions")!
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
        XCTAssertTrue(secondRange.lowerBound < decisionsRange.lowerBound, "new entry stays inside its section")
    }

    func testMultilineEntryStaysWithinSection() {
        let document = "# Today\n\n## Capture\n\n## Decisions\n"
        let result = MarkdownSection.appendingEntry("- 09:30 a\n  b", under: "## Capture", to: document)
        XCTAssertEqual(result, "# Today\n\n## Capture\n\n- 09:30 a\n  b\n\n## Decisions\n")
    }

    func testAppendToEmptyDocumentCreatesHeading() {
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: "")
        XCTAssertEqual(result, "## Capture\n\n- x\n")
    }
}
