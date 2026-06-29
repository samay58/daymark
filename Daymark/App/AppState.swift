import Foundation
import SwiftUI
import Observation
import DaymarkCore
import DaymarkStore
import DaymarkIndexer

@MainActor
@Observable
final class AppState {
    var workspaceRoot: WorkspaceRoot
    var todayText: String
    var selectedSidebarItem: SidebarItem = .today
    var isContextMarginVisible = true
    var isCommandPalettePresented = false
    var isSlipPresented = false

    /// Local full-text search results for the current command-palette query.
    var searchResults: [SearchHit] = []

    /// True when today's note changed on disk while the editor held unsaved edits.
    /// The only case where Daymark must ask the user which version wins.
    var hasExternalConflict = false

    private let calendar: Calendar
    private var lastSavedText: String
    private var hasLoaded = false
    private var autosaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    private var database: Database?
    private var indexer: WorkspaceIndexer?
    private var watcher: FileWatcher?
    private var externalDiskVersion: String?

    /// Content hashes Daymark itself has written. The watcher fires for our own atomic
    /// saves too, so any disk state whose hash is here is an echo, not an external edit.
    /// This is timing-independent, unlike comparing against a single last-saved string.
    private var selfWrittenHashes: Set<String> = []

    /// Autosave debounce. Keystrokes never wait on disk; the write fires after a quiet window.
    private static let autosaveDelay: Duration = .milliseconds(800)

    init(
        workspaceRoot: WorkspaceRoot = .resolve(override: SettingsStore.workspaceRootOverride()),
        calendar: Calendar = .current
    ) {
        self.workspaceRoot = workspaceRoot
        self.calendar = calendar
        self.todayText = SampleData.todayDocument
        self.lastSavedText = SampleData.todayDocument
    }

    // MARK: - Lifecycle

    /// Bootstraps the workspace, loads today's note into the editor, then opens the index
    /// and file watcher in the background. The editor is populated before any indexing work
    /// begins, so Today is usable immediately and typing never waits on SQLite.
    func prepareWorkspace() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let root = workspaceRoot
        let calendar = calendar

        let loaded = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try WorkspaceBootstrapper().bootstrap(root: root)
                let store = DailyNoteStore(root: root, calendar: calendar)
                try store.ensureTodayNote()
                return try store.loadToday()
            } catch {
                return nil
            }
        }.value

        if let loaded {
            todayText = loaded
            lastSavedText = loaded
        }

        await openIndex(root: root, calendar: calendar)
        startWatching(root: root)
    }

    private func openIndex(root: WorkspaceRoot, calendar: Calendar) async {
        let database = Database(configuration: DatabaseConfiguration(path: Self.databasePath(for: root)))
        do {
            try await database.open()
            _ = try await database.migrate()
        } catch {
            return
        }
        self.database = database
        let indexer = WorkspaceIndexer(root: root, database: database, calendar: calendar)
        self.indexer = indexer
        try? await indexer.indexToday()
    }

    /// Switches the active workspace root, persists the choice, and reloads Today from the
    /// new location. Tears down the previous index and watcher first so nothing leaks.
    func changeWorkspaceRoot(_ rawPath: String) async {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.setWorkspaceRootOverride(trimmed.isEmpty ? nil : trimmed)

        autosaveTask?.cancel()
        searchTask?.cancel()
        watcher?.stop()
        watcher = nil
        if let database {
            await database.close()
        }
        database = nil
        indexer = nil
        searchResults = []
        hasExternalConflict = false
        externalDiskVersion = nil
        hasLoaded = false

        workspaceRoot = .resolve(override: SettingsStore.workspaceRootOverride())
        await prepareWorkspace()
    }

    private func startWatching(root: WorkspaceRoot) {
        let dailyDirectory = root.expandedURL.appendingPathComponent("daily", isDirectory: true).path
        let watcher = FileWatcher(paths: [dailyDirectory]) { [weak self] paths in
            Task { @MainActor in self?.handleExternalChanges(paths) }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Editing and autosave

    /// Called when the editor buffer changes. Debounces an atomic Markdown write so that
    /// typing is never on the disk path, then reprojects the saved note into the index.
    func handleTodayTextChange() {
        guard hasLoaded, todayText != lastSavedText else { return }
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let root = workspaceRoot
        let calendar = calendar
        let snapshot = todayText

        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            if Task.isCancelled { return }

            // Mark the content as ours before writing, so a watcher event that races the
            // write is still recognized as an echo.
            self?.recordSelfWrite(snapshot)

            let saved = await Task.detached(priority: .utility) { () -> Bool in
                do {
                    try DailyNoteStore(root: root, calendar: calendar).save(snapshot)
                    return true
                } catch {
                    return false
                }
            }.value

            guard let self, saved else { return }
            self.lastSavedText = snapshot
            if let indexer = self.indexer {
                try? await indexer.indexToday()
            }
        }
    }

    private func recordSelfWrite(_ content: String) {
        if selfWrittenHashes.count > 64 {
            selfWrittenHashes.removeAll(keepingCapacity: true)
        }
        selfWrittenHashes.insert(ContentHasher.hash(content))
    }

    // MARK: - External edits and conflict resolution

    private func handleExternalChanges(_ paths: [String]) {
        let root = workspaceRoot
        for path in paths where path.hasSuffix(".md") {
            if let relativePath = Self.relativePath(forAbsolute: path, root: root) {
                let indexer = self.indexer
                Task { try? await indexer?.indexFile(relativePath: relativePath) }
            }
        }

        let todayFileName = (DailyNote.relativePath(for: Date(), calendar: calendar) as NSString).lastPathComponent
        if paths.contains(where: { ($0 as NSString).lastPathComponent == todayFileName }) {
            reconcileTodayWithDisk()
        }
    }

    private func reconcileTodayWithDisk() {
        let store = DailyNoteStore(root: workspaceRoot, calendar: calendar)
        guard let disk = try? store.loadToday() else { return }

        // Echo of one of our own writes (timing-independent): nothing to do.
        if selfWrittenHashes.contains(ContentHasher.hash(disk)) {
            lastSavedText = disk
            return
        }
        if disk == lastSavedText { return }

        if todayText == lastSavedText {
            // No unsaved local edits, so the external version simply wins.
            todayText = disk
            lastSavedText = disk
        } else {
            // Unsaved local edits and an external change: the user must choose.
            externalDiskVersion = disk
            hasExternalConflict = true
        }
    }

    func acceptExternalChange() {
        guard let disk = externalDiskVersion else { return }
        todayText = disk
        lastSavedText = disk
        externalDiskVersion = nil
        hasExternalConflict = false
    }

    func keepLocalVersion() {
        externalDiskVersion = nil
        hasExternalConflict = false
        // Persist the local buffer so it becomes the on-disk version.
        scheduleAutosave()
    }

    // MARK: - Search

    func runSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let database else {
            searchResults = []
            return
        }
        let repository = NoteRepository(database: database)
        searchTask = Task { [weak self] in
            let hits = (try? await repository.search(trimmed, limit: 8)) ?? []
            if Task.isCancelled { return }
            self?.searchResults = hits
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
    }

    // MARK: - Capture

    /// Saves a capture to this month's Slip file off the main actor. Independent of the Today
    /// buffer, so it never disturbs the editor. Blank captures are ignored.
    func saveCapture(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let root = workspaceRoot
        let calendar = calendar
        Task.detached(priority: .utility) {
            try? SlipStore(root: root, calendar: calendar).save(trimmed)
        }
    }

    /// Appends a capture under today's `## Capture` section. The transform runs on the
    /// in-memory buffer so it stays consistent with any unsaved edits, then the existing
    /// autosave persists it atomically and reprojects the index. Blank captures are ignored.
    func appendCaptureToToday(_ text: String) {
        appendCapture({ trimmed in
            CaptureFormatter.timestampedBullet(trimmed, at: Date(), calendar: calendar)
        }, text)
    }

    /// Promotes a capture to an open Markdown task line under today's `## Capture` section.
    /// Same buffer-first persistence as `appendCaptureToToday`. Blank captures are ignored.
    func promoteCaptureToTask(_ text: String) {
        appendCapture({ trimmed in
            CaptureFormatter.taskLine(trimmed)
        }, text)
    }

    private func appendCapture(_ formatter: (String) -> String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = formatter(trimmed)
        todayText = MarkdownSection.appendingEntry(
            entry,
            under: DailyNoteStore.captureSectionHeading,
            to: todayText
        )
        handleTodayTextChange()
    }

    // MARK: - Helpers

    static func databasePath(for root: WorkspaceRoot) -> String {
        root.expandedURL.appendingPathComponent(".daymark/daymark.db").path
    }

    static func relativePath(forAbsolute path: String, root: WorkspaceRoot) -> String? {
        let rootPath = root.expandedURL.resolvingSymlinksInPath().path
        let filePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}
