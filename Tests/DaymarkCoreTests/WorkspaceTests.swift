import XCTest
@testable import DaymarkCore

final class WorkspaceTests: XCTestCase {
    func testDefaultRootResolvesToPhoenix() {
        let root = WorkspaceRoot.resolve(override: nil, environment: [:])
        XCTAssertEqual(root.rawPath, "~/phoenix")
    }

    func testExplicitOverrideWins() {
        let root = WorkspaceRoot.resolve(
            override: "/tmp/scratch-workspace",
            environment: ["DAYMARK_WORKSPACE_ROOT": "/tmp/env-workspace"]
        )
        XCTAssertEqual(root.rawPath, "/tmp/scratch-workspace")
    }

    func testEnvironmentOverrideUsedWhenNoExplicitOverride() {
        let root = WorkspaceRoot.resolve(
            override: nil,
            environment: ["DAYMARK_WORKSPACE_ROOT": "/tmp/env-workspace"]
        )
        XCTAssertEqual(root.rawPath, "/tmp/env-workspace")
    }

    func testTildeExpands() {
        let home = NSHomeDirectory()
        let root = WorkspaceRoot(path: "~/phoenix")
        XCTAssertEqual(root.expandedPath, "\(home)/phoenix")
        XCTAssertFalse(root.expandedPath.contains("~"))
    }

    func testBootstrapCreatesOnlyDocumentedDirectories() throws {
        let root = WorkspaceRoot(path: try makeTempRoot())
        let report = try WorkspaceBootstrapper().bootstrap(root: root)

        let fm = FileManager.default
        for relative in WorkspaceBootstrapper.requiredRelativeDirectories {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: "\(root.expandedPath)/\(relative)", isDirectory: &isDir)
            XCTAssertTrue(exists && isDir.boolValue, "missing documented dir: \(relative)")
        }

        // Only documented top-level entries should exist (plus nothing extra).
        let topLevel = Set(try fm.contentsOfDirectory(atPath: root.expandedPath))
        let documentedTopLevel: Set<String> = [
            "daily", "slip", "inbox", "projects", "deals",
            "people", "meetings", "specs", "artifacts", ".daymark"
        ]
        XCTAssertTrue(topLevel.isSubset(of: documentedTopLevel), "undocumented entries: \(topLevel.subtracting(documentedTopLevel))")
        XCTAssertEqual(report.createdDirectories.count, WorkspaceBootstrapper.requiredRelativeDirectories.count)
    }

    func testBootstrapIsIdempotentAndAdditive() throws {
        let root = WorkspaceRoot(path: try makeTempRoot())
        let bootstrapper = WorkspaceBootstrapper()

        // Pre-existing user content must survive a bootstrap.
        let fm = FileManager.default
        let userFile = "\(root.expandedPath)/daily/keepme.md"
        try fm.createDirectory(atPath: "\(root.expandedPath)/daily", withIntermediateDirectories: true)
        try "important".write(toFile: userFile, atomically: true, encoding: .utf8)

        _ = try bootstrapper.bootstrap(root: root)
        let secondReport = try bootstrapper.bootstrap(root: root)

        XCTAssertEqual(secondReport.createdDirectories.count, 0, "second run should create nothing")
        XCTAssertEqual(try String(contentsOfFile: userFile, encoding: .utf8), "important")
    }

    func testExistingMarkdownRelativePathsListsOnlyMarkdownWithSubdirectoryPrefix() throws {
        let root = WorkspaceRoot(path: try makeTempRoot())
        let fm = FileManager.default
        let directory = "\(root.expandedPath)/specs/tasks"
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "a".write(toFile: "\(directory)/one.md", atomically: true, encoding: .utf8)
        try "b".write(toFile: "\(directory)/two.md", atomically: true, encoding: .utf8)
        try "c".write(toFile: "\(directory)/notes.txt", atomically: true, encoding: .utf8)

        let paths = root.existingMarkdownRelativePaths(under: "specs/tasks")

        XCTAssertEqual(paths, ["specs/tasks/one.md", "specs/tasks/two.md"])
    }

    func testExistingMarkdownRelativePathsReturnsEmptyWhenDirectoryMissing() throws {
        let root = WorkspaceRoot(path: try makeTempRoot())
        XCTAssertEqual(root.existingMarkdownRelativePaths(under: "artifacts/context-bundles"), [])
    }

    // Helper: unique temp dir we own and clean up.
    private func makeTempRoot() throws -> String {
        let base = NSTemporaryDirectory()
        let dir = "\(base)daymark-tests-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }
}
