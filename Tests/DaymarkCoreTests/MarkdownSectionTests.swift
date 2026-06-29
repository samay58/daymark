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

    func testAppendsAtEndOfSectionThatHasSubsections() {
        let document = "# Today\n\n## Capture\n\n- first\n\n### Sub\n\n- nested\n\n## Decisions\n"
        let result = MarkdownSection.appendingEntry("- second", under: "## Capture", to: document)

        XCTAssertEqual(result.components(separatedBy: "## Capture").count - 1, 1, "no duplicate heading")
        let subRange = result.range(of: "### Sub")!
        let secondRange = result.range(of: "- second")!
        let decisionsRange = result.range(of: "## Decisions")!
        XCTAssertTrue(subRange.lowerBound < secondRange.lowerBound, "entry lands after the subsection")
        XCTAssertTrue(secondRange.lowerBound < decisionsRange.lowerBound, "entry stays inside the level-2 section")
    }

    func testDoesNotTreatFencedCodeHeadingsAsBoundaries() {
        let document = "# Today\n\n## Capture\n\n```\n## not a heading\n```\n\n## Decisions\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)

        XCTAssertTrue(result.contains("```\n## not a heading\n```"), "fenced code block must survive intact")
        let codeRange = result.range(of: "## not a heading")!
        let entryRange = result.range(of: "- x")!
        let decisionsRange = result.range(of: "## Decisions")!
        XCTAssertTrue(codeRange.lowerBound < entryRange.lowerBound, "entry lands after the code block, not inside it")
        XCTAssertTrue(entryRange.lowerBound < decisionsRange.lowerBound, "entry stays inside the Capture section")
    }

    func testDoesNotMatchHeadingInsideFencedCode() {
        // A "## Capture" that appears only inside a code block must not be treated as the
        // real section; the real heading is added at the end instead.
        let document = "# Today\n\n```\n## Capture\n```\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)

        XCTAssertTrue(result.contains("```\n## Capture\n```"), "the in-code heading is left untouched")
        XCTAssertEqual(result.components(separatedBy: "## Capture").count - 1, 2, "one in-code, one real heading")
        XCTAssertTrue(result.hasSuffix("## Capture\n\n- x\n"), "a real Capture section is appended at the end")
    }

    func testMatchesHeadingInCRLFDocumentWithoutDuplicating() {
        let document = "# Today\r\n\r\n## Capture\r\n\r\n## Decisions\r\n"
        let result = MarkdownSection.appendingEntry("- x", under: "## Capture", to: document)

        XCTAssertEqual(result.components(separatedBy: "## Capture").count - 1, 1,
                       "a CRLF heading must still be matched, not duplicated")
        XCTAssertTrue(result.contains("- x"))
        XCTAssertFalse(result.contains("\r"), "output is normalized to LF")
        let entryRange = result.range(of: "- x")!
        let decisionsRange = result.range(of: "## Decisions")!
        XCTAssertTrue(entryRange.lowerBound < decisionsRange.lowerBound, "entry stays inside the section")
    }
}
