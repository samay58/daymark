import XCTest
import DaymarkCore

final class WorkspacePathTests: XCTestCase {
    private func makeRoot() throws -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-path-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return WorkspaceRoot(path: path)
    }

    func testContainedFileAcceptsWorkspaceRelativePath() throws {
        let root = try makeRoot()
        let resolved = try root.containedFile("daily/2026/06/2026-06-29.md")
        XCTAssertEqual(resolved.relativePath, "daily/2026/06/2026-06-29.md")
        XCTAssertTrue(resolved.url.path.hasSuffix("daily/2026/06/2026-06-29.md"))
    }

    func testContainedFileNormalizesInnerParentSegments() throws {
        let root = try makeRoot()
        let resolved = try root.containedFile("daily/sub/../x.md")
        XCTAssertEqual(resolved.relativePath, "daily/x.md")
    }

    func testContainedFileRejectsParentEscape() throws {
        let root = try makeRoot()
        XCTAssertThrowsError(try root.containedFile("../../etc/passwd")) { error in
            XCTAssertEqual(error as? WorkspacePathError, .outsideWorkspace("../../etc/passwd"))
        }
    }

    func testContainedFileRejectsAbsolutePathOutsideRoot() throws {
        let root = try makeRoot()
        XCTAssertThrowsError(try root.containedFile("/etc/hosts")) { error in
            XCTAssertEqual(error as? WorkspacePathError, .outsideWorkspace("/etc/hosts"))
        }
    }
}
