import Foundation
import SwiftUI
import AppKit
import Observation
import DaymarkCore
import DaymarkStore
import DaymarkIndexer
import DaymarkAgents

/// A Codex task file that has been written, paired with the exact draft it came from.
/// Bundling the two makes the "task created" phase a single value, so the path and draft
/// can never disagree.
struct CreatedCodexTask: Equatable {
    var relativePath: String
    var draft: CodexTaskDraft
}

@MainActor
@Observable
final class AppState {
    var workspaceRoot: WorkspaceRoot
    var todayText: String {
        didSet { recomputeBufferDerivations() }
    }
    /// Derivations of the editor buffer, memoized once per mutation in todayText.didSet so the
    /// dynamic-block gating getters never re-scan and re-hash the whole note during a
    /// context-margin body pass (which reads three of those getters per keystroke).
    private(set) var todayContentHash = ""
    private(set) var todayHasDynamicBlockCommand = false
    var selectedSidebarItem: SidebarItem = .today
    var isContextMarginVisible = true
    var isCommandPalettePresented = false
    var isSlipPresented = false
    var editorSelection = SelectionModel()
    var codexTaskDraft: CodexTaskDraft?
    var codexTaskMessage: String?
    var codexContextBundle: CodexContextBundle?
    var codexContextBundleMessage: String?
    var dynamicBlockPreview: DynamicBlockRefreshPreview?
    var dynamicBlockMessage: String?
    var isPlanningDynamicBlocks = false
    var isApplyingDynamicBlocks = false
    private var codexTaskPathBasis: Set<String> = []
    private var codexTaskDateBasis: Date?
    /// The created task file and the exact draft it was written from, kept together so the
    /// "task created" phase cannot be half-set (both-or-neither is unrepresentable).
    private var createdCodexTask: CreatedCodexTask?

    /// The created task file's path, read by the context-margin view.
    var createdCodexTaskRelativePath: String? { createdCodexTask?.relativePath }

    /// Whether the current draft / bundle can be written. The views read these instead of
    /// constructing a file writer just to evaluate button enable state (the predicate is the
    /// single source of truth, shared with the writers' `validate`).
    var canCreateCodexTaskFile: Bool { codexTaskDraft?.isWritable ?? false }
    var canCreateCodexContextBundle: Bool { codexContextBundle?.isWritable ?? false }
    var canRefreshDynamicBlocks: Bool {
        didLoadToday && todayHasDynamicBlockCommand
    }
    var canApplyDynamicBlocks: Bool {
        guard let preview = dynamicBlockPreview else { return false }
        return todayContentHash == preview.sourceContentHash
            && !isPlanningDynamicBlocks
            && !isApplyingDynamicBlocks
    }
    var isDynamicBlockPreviewStale: Bool {
        guard let preview = dynamicBlockPreview else { return false }
        return todayContentHash != preview.sourceContentHash
    }

    /// Local full-text search results for the current command-palette query.
    var searchResults: [SearchHit] = []
    var openLoopGroups: [OpenLoopGroup] = []
    var isRefreshingOpenLoops = false

    var openLoopCount: Int {
        openLoopGroups.reduce(0) { $0 + $1.tasks.count }
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
    private var didLoadToday = false
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
        recomputeBufferDerivations()
        observeTermination()
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

    /// Recomputes the memoized buffer derivations the dynamic-block gating reads. Called once
    /// per todayText mutation (didSet) and once at init, so the gating getters stay O(1).
    private func recomputeBufferDerivations() {
        todayContentHash = ContentHasher.hash(todayText)
        todayHasDynamicBlockCommand = DynamicBlockParser().containsKnownCommand(in: todayText)
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

    // MARK: - Open Loops

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

    // MARK: - Dynamic Blocks

    var showsDynamicBlockRefreshPanel: Bool {
        canRefreshDynamicBlocks
            || dynamicBlockPreview != nil
            || dynamicBlockMessage != nil
            || isPlanningDynamicBlocks
            || isApplyingDynamicBlocks
    }

    func previewDynamicBlocksRefresh() async {
        guard didLoadToday else {
            dynamicBlockPreview = nil
            dynamicBlockMessage = "Load today's note before refreshing dynamic blocks."
            isContextMarginVisible = true
            return
        }
        guard todayHasDynamicBlockCommand else {
            dynamicBlockPreview = nil
            dynamicBlockMessage = "No dynamic block commands in this note."
            isContextMarginVisible = true
            return
        }

        isPlanningDynamicBlocks = true
        dynamicBlockMessage = nil
        isContextMarginVisible = true
        let root = workspaceRoot
        let sourcePath = todayRelativePath
        let markdown = todayText
        let calendar = calendar

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try DynamicBlockRefreshService().preview(
                    markdown: markdown,
                    sourcePath: sourcePath,
                    root: root,
                    referenceDate: Date(),
                    calendar: calendar
                )
            }
        }.value

        isPlanningDynamicBlocks = false
        switch result {
        case .success(let preview):
            if preview.plan.patches.isEmpty {
                dynamicBlockPreview = nil
                dynamicBlockMessage = "No dynamic block commands in this note."
            } else {
                dynamicBlockPreview = preview
                dynamicBlockMessage = nil
            }
        case .failure(let error):
            dynamicBlockPreview = nil
            dynamicBlockMessage = Self.message(for: error)
        }
    }

    func applyDynamicBlocksRefresh() async {
        guard let preview = dynamicBlockPreview else {
            dynamicBlockMessage = "Preview dynamic blocks before applying."
            isContextMarginVisible = true
            return
        }
        guard todayContentHash == preview.sourceContentHash else {
            dynamicBlockMessage = "Preview is stale. Refresh the preview before applying."
            return
        }

        autosaveTask?.cancel()
        isApplyingDynamicBlocks = true
        dynamicBlockMessage = nil
        let root = workspaceRoot
        let markdown = todayText

        // Compute the applied Markdown on the main actor and record it as our own write before
        // the disk write, matching scheduleAutosave's echo-guard ordering so a watcher event
        // racing the write is recognized as an echo. The detached task runs the same
        // deterministic apply() and performs the workspace-confined write.
        let updated: String
        do {
            updated = try preview.plan.apply(to: markdown)
        } catch {
            isApplyingDynamicBlocks = false
            dynamicBlockMessage = Self.message(for: error)
            return
        }
        recordSelfWrite(updated)

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try DynamicBlockRefreshService().apply(
                    preview: preview,
                    currentMarkdown: markdown,
                    root: root
                )
            }
        }.value

        isApplyingDynamicBlocks = false
        switch result {
        case .success(let result):
            dynamicBlockPreview = nil
            // A keystroke may have landed between the snapshot above and here. Adopt the
            // applied Markdown only if the buffer still matches what was previewed; otherwise
            // the user has unsaved edits and the freshly-written disk version is a conflict to
            // resolve, not a buffer to clobber.
            if todayContentHash == preview.sourceContentHash {
                lastSavedText = result.updatedMarkdown
                todayText = result.updatedMarkdown
                dynamicBlockMessage = result.cacheWarning == nil
                    ? "Updated dynamic blocks."
                    : "Updated dynamic blocks. Cache metadata will rebuild later."
            } else {
                externalDiskVersion = result.updatedMarkdown
                hasExternalConflict = true
                dynamicBlockMessage = "Note changed during refresh. Resolve the conflict to keep the update."
            }
            if let indexer {
                try? await indexer.indexToday()
            }
            await refreshOpenLoops()
        case .failure(let error):
            dynamicBlockMessage = Self.message(for: error)
        }
    }

    func dismissDynamicBlocksRefresh() {
        dynamicBlockPreview = nil
        dynamicBlockMessage = nil
        isPlanningDynamicBlocks = false
        isApplyingDynamicBlocks = false
    }

    // MARK: - Codex task handoff

    // True once a task file has been created, while a bundle is previewed, or when a bundle
    // message needs to stay on screen. Drives whether the right margin shows the bundle panel.
    var showsContextBundlePanel: Bool {
        createdCodexTask != nil
            || codexContextBundle != nil
            || codexContextBundleMessage != nil
    }

    func previewCodexTaskFromSelection() {
        do {
            let sourcePath = editorSelection.sourcePath ?? todayRelativePath
            let selection = try SourceSelector().select(
                text: todayText,
                selectedRange: editorSelection.selectedRange,
                cursorLocation: editorSelection.cursorLocation,
                sourcePath: sourcePath
            )
            let existingPaths = workspaceRoot.existingMarkdownRelativePaths(under: "specs/tasks")
            let previewDate = Date()
            codexTaskPathBasis = existingPaths
            codexTaskDateBasis = previewDate
            clearCodexContextBundleState()
            codexTaskDraft = try PreviewBuilder().codexTaskPreview(
                source: selection,
                date: previewDate,
                existingRelativePaths: existingPaths
            )
            codexTaskMessage = nil
            isContextMarginVisible = true
        } catch {
            codexTaskDraft = nil
            clearCodexContextBundleState()
            codexTaskMessage = "Select text or place the cursor inside a note block first."
            isContextMarginVisible = true
        }
    }

    func updateCodexTaskDraftTitle(_ title: String) { editCodexTaskDraftFields(title: title) }
    func updateCodexTaskDraftGoal(_ goal: String) { editCodexTaskDraftFields(goal: goal) }
    func updateCodexTaskDraftConstraints(_ text: String) {
        editCodexTaskDraftFields(constraints: Self.lines(from: text))
    }
    func updateCodexTaskDraftAcceptanceCriteria(_ text: String) {
        editCodexTaskDraftFields(acceptanceCriteria: Self.lines(from: text))
    }

    /// Threads the date and path basis once and rewrites only the supplied field(s); a nil
    /// field keeps the draft's current value. Swift default args cannot reference the runtime
    /// draft, so each unset field resolves against the draft inside the edit closure.
    private func editCodexTaskDraftFields(
        title: String? = nil,
        goal: String? = nil,
        constraints: [String]? = nil,
        acceptanceCriteria: [String]? = nil
    ) {
        updateCodexTaskDraft { draft in
            draft.withEditedFields(
                title: title ?? draft.title,
                goal: goal ?? draft.goal,
                constraints: constraints ?? draft.constraints,
                acceptanceCriteria: acceptanceCriteria ?? draft.acceptanceCriteria,
                date: codexTaskDateBasis ?? Date(),
                existingRelativePaths: codexTaskPathBasis
            )
        }
    }

    private func updateCodexTaskDraft(_ edit: (CodexTaskDraft) -> CodexTaskDraft) {
        guard let codexTaskDraft else { return }
        self.codexTaskDraft = edit(codexTaskDraft)
        codexTaskMessage = nil
        clearCodexContextBundleState()
    }

    func createCodexTaskFile() {
        guard let codexTaskDraft else {
            codexTaskMessage = "Create a preview before writing a task file."
            return
        }
        do {
            let result = try CodexTaskFileWriter().write(codexTaskDraft, root: workspaceRoot)
            codexTaskPathBasis.insert(result.relativePath)
            let writtenDraft = codexTaskDraft.withSuggestedFilePath(result.relativePath)
            self.codexTaskDraft = writtenDraft
            createdCodexTask = CreatedCodexTask(relativePath: result.relativePath, draft: writtenDraft)
            codexContextBundle = nil
            codexContextBundleMessage = nil
            codexTaskMessage = "Created \(result.relativePath)"
        } catch CodexTaskFileWriter.Error.blankDraft {
            codexTaskMessage = "Fill in a title, goal, source, and excerpt before creating the file."
        } catch CodexTaskFileWriter.Error.invalidPath {
            codexTaskMessage = "The task file path must stay under specs/tasks."
        } catch {
            codexTaskMessage = "Could not create the task file."
        }
    }

    func dismissCodexTaskDraft() {
        codexTaskDraft = nil
        codexTaskMessage = nil
        clearCodexContextBundleState()
        codexTaskPathBasis = []
        codexTaskDateBasis = nil
    }

    private func clearCodexContextBundleState() {
        createdCodexTask = nil
        codexContextBundle = nil
        codexContextBundleMessage = nil
    }

    func previewCodexContextBundle() {
        guard let createdCodexTask else {
            codexContextBundle = nil
            codexContextBundleMessage = "Create a task file before previewing a context bundle."
            return
        }
        let existingPaths = workspaceRoot.existingMarkdownRelativePaths(under: "artifacts/context-bundles")
        codexContextBundle = CodexContextBundle.from(
            draft: createdCodexTask.draft,
            taskRelativePath: createdCodexTask.relativePath,
            date: Date(),
            existingRelativePaths: existingPaths
        )
        codexContextBundleMessage = nil
    }

    func createCodexContextBundle() {
        guard let codexContextBundle else {
            codexContextBundleMessage = "Preview a context bundle before creating it."
            return
        }
        do {
            let result = try CodexContextBundleWriter().write(codexContextBundle, root: workspaceRoot)
            self.codexContextBundle = codexContextBundle.withSuggestedFilePath(result.relativePath)
            codexContextBundleMessage = "Created \(result.relativePath)"
        } catch CodexContextBundleWriter.Error.blankBundle {
            codexContextBundleMessage = "The bundle needs a task, goal, source, and excerpt before writing."
        } catch CodexContextBundleWriter.Error.invalidPath {
            codexContextBundleMessage = "The bundle file path must stay under artifacts/context-bundles."
        } catch {
            codexContextBundleMessage = "Could not create the context bundle."
        }
    }

    func dismissCodexContextBundle() {
        codexContextBundle = nil
        codexContextBundleMessage = nil
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

    private static func lines(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet.newlines)
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "Could not refresh dynamic blocks."
    }
}
