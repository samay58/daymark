import XCTest
@testable import DaymarkCore

final class MeetingPrepTests: XCTestCase {
    func testEventSnapshotParsesValidJSON() throws {
        let snapshot = try MeetingEventSnapshot.decode(
            data: Data("""
            {
              "title": "Acme Partner Sync",
              "startsAt": "2026-07-01T14:30:00Z",
              "endsAt": "2026-07-01T15:00:00Z",
              "attendees": ["Sarah Chen", "Maya Lee"],
              "location": "Zoom",
              "tags": ["#deal/acme"],
              "notes": "Discuss renewal questions."
            }
            """.utf8),
            sourceIdentifier: "/tmp/event.json"
        )

        XCTAssertEqual(snapshot.title, "Acme Partner Sync")
        XCTAssertEqual(snapshot.attendees, ["Sarah Chen", "Maya Lee"])
        XCTAssertEqual(snapshot.location, "Zoom")
        XCTAssertEqual(snapshot.tags, ["#deal/acme"])
        XCTAssertEqual(snapshot.notes, "Discuss renewal questions.")
        XCTAssertEqual(snapshot.sourceIdentifier, "/tmp/event.json")
    }

    func testEventSnapshotRejectsBlankTitleAndInvalidDate() {
        XCTAssertThrowsError(try MeetingEventSnapshot.decode(
            data: Data(#"{"title":" ","startsAt":"2026-07-01T14:30:00Z","endsAt":"2026-07-01T15:00:00Z"}"#.utf8),
            sourceIdentifier: nil
        )) { error in
            XCTAssertEqual(error as? MeetingEventSnapshot.Error, .missingTitle)
        }

        XCTAssertThrowsError(try MeetingEventSnapshot.decode(
            data: Data(#"{"title":"Acme","startsAt":"soon","endsAt":"2026-07-01T15:00:00Z"}"#.utf8),
            sourceIdentifier: nil
        )) { error in
            XCTAssertEqual(error as? MeetingEventSnapshot.Error, .invalidDate("soon"))
        }
    }

    func testMeetingPrepMarkdownIncludesEventMetadataAndLocalCitations() {
        let draft = MeetingPrepDraft(
            event: sampleEvent(),
            context: MeetingPrepContext(
                sources: [
                    MeetingPrepSource(title: "Acme Notes", relativePath: "projects/acme.md", tags: ["#deal/acme"])
                ],
                openTasks: [
                    TaskItem(
                        title: "Send updated model #deal/acme",
                        status: .open,
                        tags: ["#deal/acme"],
                        notePath: "daily/2026/06/2026-06-30.md",
                        lineNumber: 12,
                        originalLine: "- [ ] Send updated model #deal/acme"
                    )
                ],
                codexArtifacts: [
                    DynamicBlockCodexContextArtifact(
                        kind: .taskSpec,
                        title: "Tighten Acme model",
                        relativePath: "specs/tasks/2026-06-30-tighten-acme-model.md",
                        tags: ["#deal/acme"],
                        sourcePaths: ["projects/acme.md"]
                    )
                ],
                questions: [
                    MeetingPrepQuestion(text: "What renewal risk changed?", relativePath: "projects/acme.md", lineNumber: 8)
                ]
            ),
            suggestedFilePath: "meetings/2026-07-01-acme-partner-sync.md"
        )

        let markdown = draft.markdown()

        XCTAssertTrue(markdown.contains("# Meeting Prep: Acme Partner Sync"))
        XCTAssertTrue(markdown.contains("Time: 2026-07-01 2:30 PM"))
        XCTAssertTrue(markdown.contains("Attendees: Sarah Chen, Maya Lee"))
        XCTAssertTrue(markdown.contains("Source event: `/tmp/event.json`"))
        XCTAssertTrue(markdown.contains("- Source: Acme Notes (`projects/acme.md`)"))
        XCTAssertTrue(markdown.contains("- [ ] Send updated model #deal/acme (`daily/2026/06/2026-06-30.md:12`)"))
        XCTAssertTrue(markdown.contains("- Task spec: Tighten Acme model (`specs/tasks/2026-06-30-tighten-acme-model.md`)"))
        XCTAssertTrue(markdown.contains("- What renewal risk changed? (`projects/acme.md:8`)"))
        XCTAssertFalse(markdown.contains("TBD"))
    }

    func testMeetingPrepWriterCreatesCollisionSafeFilesAndLeavesSourcesUnchanged() throws {
        let root = WorkspaceRoot(path: "\(NSTemporaryDirectory())daymark-meeting-prep-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.expandedPath) }
        let source = root.expandedURL.appendingPathComponent("projects/acme.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Acme\n".write(to: source, atomically: true, encoding: .utf8)
        let draft = MeetingPrepDraft(
            event: sampleEvent(),
            context: .empty,
            suggestedFilePath: "meetings/2026-07-01-acme-partner-sync.md"
        )

        let first = try MeetingPrepWriter().write(draft, root: root)
        let second = try MeetingPrepWriter().write(draft, root: root)

        XCTAssertEqual(first.relativePath, "meetings/2026-07-01-acme-partner-sync.md")
        XCTAssertEqual(second.relativePath, "meetings/2026-07-01-acme-partner-sync-2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "# Acme\n")
    }

    func testMeetingPrepWriterRejectsBlankDraftAndInvalidPath() {
        var blank = MeetingPrepDraft(
            event: sampleEvent(title: " "),
            context: .empty,
            suggestedFilePath: "meetings/2026-07-01-acme-partner-sync.md"
        )
        XCTAssertThrowsError(try MeetingPrepWriter().validate(blank)) { error in
            XCTAssertEqual(error as? MeetingPrepWriter.Error, .blankDraft)
        }

        blank = MeetingPrepDraft(
            event: sampleEvent(),
            context: .empty,
            suggestedFilePath: "../outside.md"
        )
        XCTAssertThrowsError(try MeetingPrepWriter().validate(blank)) { error in
            XCTAssertEqual(error as? MeetingPrepWriter.Error, .invalidPath)
        }
    }

    private func sampleEvent(title: String = "Acme Partner Sync") -> MeetingEventSnapshot {
        MeetingEventSnapshot(
            title: title,
            startsAt: Date(timeIntervalSince1970: 1_782_916_200),
            endsAt: Date(timeIntervalSince1970: 1_782_918_000),
            location: "Zoom",
            attendees: ["Sarah Chen", "Maya Lee"],
            tags: ["#deal/acme"],
            notes: "Discuss renewal questions.",
            sourceIdentifier: "/tmp/event.json"
        )
    }
}
