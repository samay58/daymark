import Foundation
import SwiftUI
import AppKit
import Observation
import DaymarkCore
import DaymarkStore
import DaymarkIndexer
import DaymarkAgents

@MainActor
@Observable
final class AppState {
    var workspaceRoot: WorkspaceRoot {
        didSet {
            codex.workspaceRoot = workspaceRoot
            dynamicBlocks.workspaceRoot = workspaceRoot
        }
    }
    var todayText: String {
        didSet { dynamicBlocks.bufferDidChange() }
    }
    var isOpenLoopsOverlayPresented = false
    var rolledOverCount = 0
    var isCommandPalettePresented = false
    var commandPalettePrefill: String?
    var isSlipPresented = false
    var editorSelection = SelectionModel()
    /// A short message that stands in for the brief strip for a few seconds, for outcomes with
    /// no surface of their own (nothing to refresh, no selection for Codex).
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    let codex: CodexFlowModel
    let dynamicBlocks: DynamicBlockRefreshModel
    /// Screen rect for a character range in the editor, installed by the editor so a popover can
    /// anchor to a selection or a line. Called only when a popover opens, never while typing.
    @ObservationIgnored var rectForCharacterRange: ((NSRange) -> NSRect?)?

    /// Local full-text search results for the current command-palette query.
    var searchResults: [SearchHit] = []
    var openLoopGroups: [OpenLoopGroup] = []
    var isRefreshingOpenLoops = false

    var openLoopCount: Int {
        openLoopGroups.reduce(0) { $0 + $1.tasks.count }
    }

    /// True while an autosave write is pending or in flight. Backs the brief strip's save state.
    var isSaving: Bool {
        todayText != lastSavedText
    }

    var todayRelativePath: String {
        DailyNote.relativePath(for: Date(), calendar: calendar)
    }

    /// True when today's note changed on disk while the editor held unsaved edits.
    /// The only case where Daymark must ask the user which version wins.
    var hasExternalConflict = false

    private let calendar: Calendar
    private var lastSavedText: String
    /// Reentrancy guard for `prepareWorkspace`. Set true before the load starts.
    private var hasLoaded = false
    /// True only once today's real note is in the buffer. Persistence is gated on this so the
    /// initial `SampleData` placeholder (or a failed load) can never be written over the real
    /// daily note on disk.
    private var didLoadToday = false {
        didSet { dynamicBlocks.isNoteLoaded = didLoadToday }
    }
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
        self.codex = CodexFlowModel(workspaceRoot: workspaceRoot)
        self.dynamicBlocks = DynamicBlockRefreshModel(workspaceRoot: workspaceRoot, calendar: calendar)
        self.calendar = calendar
        self.todayText = SampleData.todayDocument
        self.lastSavedText = SampleData.todayDocument
        connectDynamicBlocks()
        observeTermination()
    }

    private func connectDynamicBlocks() {
        dynamicBlocks.hooks = DynamicBlockRefreshModel.Hooks(
            sourcePath: { [weak self] in self?.todayRelativePath ?? "" },
            buffer: { [weak self] in self?.todayText ?? "" },
            adoptApplied: { [weak self] markdown in
                self?.lastSavedText = markdown
                self?.todayText = markdown
            },
            raiseConflict: { [weak self] disk in
                self?.externalDiskVersion = disk
                self?.hasExternalConflict = true
            },
            recordSelfWrite: { [weak self] content in self?.recordSelfWrite(content) },
            cancelAutosave: { [weak self] in self?.autosaveTask?.cancel() },
            showNotice: { [weak self] text in self?.showNotice(text) },
            reindexToday: { [weak self] in
                if let indexer = self?.indexer { try? await indexer.indexToday() }
            },
            refreshOpenLoops: { [weak self] in await self?.refreshOpenLoops() }
        )
        dynamicBlocks.bufferDidChange()
    }

    /// Flush any pending Today write synchronously when the app is quitting, so a capture or
    /// edit made within the autosave debounce window is not lost on exit.
    private func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingWrite() }
        }
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
            didLoadToday = true
        }

        await openIndex(root: root, calendar: calendar)
        startWatching(root: root)
        dynamicBlocks.reloadCache()
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
        await runRolloverIfSafe(root: root, database: database, calendar: calendar)
        await refreshOpenLoops()
    }

    private func runRolloverIfSafe(root: WorkspaceRoot, database: Database, calendar: Calendar) async {
        guard didLoadToday else { return }
        let baseline = lastSavedText
        let result = try? await TaskRolloverEngine(root: root, database: database, calendar: calendar).run(apply: true)
        guard result?.applied == true,
              let disk = try? DailyNoteStore(root: root, calendar: calendar).loadToday() else {
            return
        }
        rolledOverCount = result?.entries.count ?? 0

        if todayText == baseline {
            recordSelfWrite(disk)
            todayText = disk
            lastSavedText = disk
        } else {
            externalDiskVersion = disk
            hasExternalConflict = true
        }
    }

    /// Switches the active workspace root, persists the choice, and reloads Today from the
    /// new location. Tears down the previous index and watcher first so nothing leaks.
    func changeWorkspaceRoot(_ rawPath: String) async {
        // Before any await, so an apply or planning run still in flight sees the switch.
        dynamicBlocks.workspaceWillChange()
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
        didLoadToday = false
        rolledOverCount = 0

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
        guard didLoadToday, todayText != lastSavedText else { return }
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
            // No unsaved local edits, so the external version simply wins. An external write
            // (for example a CLI `blocks refresh --apply` against the open workspace) can have
            // changed .daymark/dynamic-blocks.json too, so refresh the card metadata cache here
            // rather than leaving cards showing a stale "generated" time.
            todayText = disk
            lastSavedText = disk
            dynamicBlocks.reloadCache()
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

    // MARK: - Command palette

    /// Opens the command palette. A nil prefill leaves any existing query untouched (today's
    /// behavior); a non-nil string is consumed once by the palette on appear.
    func showCommandPalette(prefill: String?) {
        commandPalettePrefill = prefill
        isCommandPalettePresented = true
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

    // MARK: - Open Loops

    /// Returns to the note by closing the overlays that sit over it.
    func showToday() {
        isOpenLoopsOverlayPresented = false
        isCommandPalettePresented = false
    }

    /// The menu, palette, toolbar, and brief strip all open Open Loops through here, so every
    /// entry point refreshes the list the same way.
    func toggleOpenLoopsOverlay() {
        isOpenLoopsOverlayPresented.toggle()
        if isOpenLoopsOverlayPresented {
            Task { await refreshOpenLoops() }
        }
    }

    func refreshOpenLoops() async {
        guard let database else {
            openLoopGroups = []
            return
        }
        isRefreshingOpenLoops = true
        let tasks = (try? await database.openTasks()) ?? []
        openLoopGroups = OpenLoops.grouped(tasks: tasks, on: Date(), calendar: calendar)
        isRefreshingOpenLoops = false
    }

    // MARK: - Notices

    private static let noticeDuration: Duration = .seconds(4)

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Editor geometry

    /// Screen rect for a range of the buffer, for anchoring a popover. Nil when the editor has
    /// not installed `rectForCharacterRange` or the range no longer fits the buffer.
    func screenRect(forCharacterRange range: NSRange) -> NSRect? {
        guard let rectForCharacterRange,
              NSMaxRange(range) <= (todayText as NSString).length,
              let rect = rectForCharacterRange(range),
              rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return rect
    }

    // MARK: - Codex task handoff

    /// Opens the Codex composer for the selection, or the block under the caret.
    func previewCodexTaskFromSelection() {
        let started = codex.startDraft(
            text: todayText,
            selection: editorSelection,
            fallbackSourcePath: todayRelativePath
        )
        if !started {
            showNotice("Select text or place the cursor in a block first")
        }
    }

    // MARK: - Capture

    /// Saves a capture to this month's Slip file. The write is synchronous and atomic, so the
    /// capture is durable before the panel dismisses, and it returns false (losing nothing) if
    /// the write fails or the text is blank. This is an explicit save action, not the Today
    /// editor's keystroke path, so the no-blocking-typing invariant still holds.
    @discardableResult
    func saveCapture(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try SlipStore(root: workspaceRoot, calendar: calendar).save(trimmed)
            return true
        } catch {
            return false
        }
    }

    /// Appends a capture under today's `## Capture` section. The transform runs on the
    /// in-memory buffer so it stays consistent with any unsaved edits, then autosave persists
    /// it atomically and reprojects the index. Returns false only for blank text.
    @discardableResult
    func appendCaptureToToday(_ text: String) -> Bool {
        appendCapture({ trimmed in
            CaptureFormatter.timestampedBullet(trimmed, at: Date(), calendar: calendar)
        }, text)
    }

    /// Promotes a capture to an open Markdown task line under today's `## Capture` section.
    /// Same buffer-first persistence as `appendCaptureToToday`. Returns false only for blank text.
    @discardableResult
    func promoteCaptureToTask(_ text: String) -> Bool {
        appendCapture({ trimmed in
            CaptureFormatter.taskLine(trimmed)
        }, text)
    }

    @discardableResult
    private func appendCapture(_ formatter: (String) -> String, _ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Before the real note is loaded the buffer still holds the SampleData placeholder, and
        // writing it back would clobber the real daily note. Route the capture to the Slip file
        // instead, so it is never lost and the daily note is never touched.
        guard didLoadToday else { return saveCapture(trimmed) }
        let entry = formatter(trimmed)
        todayText = MarkdownSection.appendingEntry(
            entry,
            under: DailyNoteStore.captureSectionHeading,
            to: todayText
        )
        handleTodayTextChange()
        return true
    }

    /// Synchronously writes any pending Today edits before the app exits, closing the window
    /// where a capture or edit lives only in the debounced autosave. Called on app termination.
    func flushPendingWrite() {
        autosaveTask?.cancel()
        guard didLoadToday, todayText != lastSavedText else { return }
        recordSelfWrite(todayText)
        try? DailyNoteStore(root: workspaceRoot, calendar: calendar).save(todayText)
        lastSavedText = todayText
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
