import Foundation
import SwiftUI
import AppKit
import Observation
import DaymarkCore
import DaymarkStore
import DaymarkIndexer
import DaymarkAgents

/// A dynamic block card's pending change: the one-line summary, the incoming Markdown the card
/// shows in place of its current body, and whether Apply is allowed right now.
struct DynamicBlockCardPreview: Equatable {
    var summaryText: String
    var incomingMarkdown: String
    var canApply: Bool
    var isStale: Bool
}

@MainActor
@Observable
final class AppState {
    var workspaceRoot: WorkspaceRoot {
        didSet { codex.workspaceRoot = workspaceRoot }
    }
    var todayText: String {
        didSet { recomputeBufferDerivations() }
    }
    /// Derivations of the editor buffer, memoized once per mutation in todayText.didSet so
    /// dynamic-block buttons and cards never re-scan and re-hash the whole note while typing.
    private(set) var todayContentHash = ""
    private(set) var todayHasDynamicBlockCommand = false
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
    /// Screen rect for a character range in the editor, installed by the editor so a popover can
    /// anchor to a selection or a line. Called only when a popover opens, never while typing.
    @ObservationIgnored var rectForCharacterRange: ((NSRange) -> NSRect?)?

    /// The pending refresh preview, if any. Cards and the new-block popover read their own part.
    private(set) var dynamicBlockSession: DynamicBlockRefreshSession?
    /// Flips only when the buffer diverges from (or returns to) the previewed Markdown, so card
    /// bodies observe one bool instead of the per-keystroke content hash.
    private(set) var isDynamicBlockPreviewStale = false
    private(set) var isPlanningDynamicBlocks = false
    private(set) var isApplyingDynamicBlocks = false
    /// Failures scoped to one card, keyed by region hash, shown in that card's footer.
    private(set) var dynamicBlockCardErrors: [String: String] = [:]
    /// Failure shown inside the new-block popover.
    private(set) var newDynamicBlocksError: String?
    /// Every planning run bumps this; a result from an older run (cancelled or superseded) is
    /// ignored, since the detached planner itself cannot be interrupted.
    @ObservationIgnored private var dynamicBlockGeneration = 0
    @ObservationIgnored private var dynamicBlockPlanningTask: Task<Result<DynamicBlockRefreshSession, any Error>, Never>?
    /// Cache records for today's note, keyed by command hash, backing each card's
    /// "generated <relative time>" label. Reloaded after workspace load and after apply.
    private var dynamicBlockCacheRecords: [String: DynamicBlockCacheRecord] = [:]

    var canRefreshDynamicBlocks: Bool {
        didLoadToday && todayHasDynamicBlockCommand
    }
    var isNewDynamicBlocksPopoverPresented: Bool {
        !(dynamicBlockSession?.newBlocks.isEmpty ?? true)
    }
    /// The composer popover is open exactly while a draft exists.
    var isCodexPopoverPresented: Bool { codex.composer != nil }
    var codexReceipt: CodexFlowModel.Receipt? { codex.receipt }
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
        self.codex = CodexFlowModel(workspaceRoot: workspaceRoot)
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
        reloadDynamicBlockCache()
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
        // A pending preview was planned against the old root's note.
        dismissDynamicBlocksRefresh()

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
        updateDynamicBlockStaleness()
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
            reloadDynamicBlockCache()
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

    // MARK: - Dynamic Blocks

    /// Where a refresh or apply started, which decides where its failure is reported.
    private enum DynamicBlockOrigin: Equatable {
        case global
        case card(String)
        case newBlocks
    }

    private typealias PlanningRun = (generation: Int, task: Task<Result<DynamicBlockRefreshSession, any Error>, Never>)

    /// Menu, palette, and shortcut refresh. Failures and "nothing to do" go to the notice.
    func previewDynamicBlocksRefresh() async {
        await previewDynamicBlocks(origin: .global)
    }

    /// A card's own refresh button. Failures show in that card's footer.
    func previewDynamicBlocksRefresh(fromCard regionHash: String) async {
        await previewDynamicBlocks(origin: .card(regionHash))
    }

    private func previewDynamicBlocks(origin: DynamicBlockOrigin) async {
        guard !isApplyingDynamicBlocks else { return }
        guard didLoadToday else {
            report(DynamicBlockCopy.notLoaded, origin: origin)
            return
        }
        guard todayHasDynamicBlockCommand else {
            setDynamicBlockSession(nil)
            showNotice(DynamicBlockCopy.noCommands)
            return
        }
        if case .card(let hash) = origin { dynamicBlockCardErrors[hash] = nil }

        let run = startDynamicBlockPlanning()
        guard let result = await finishDynamicBlockPlanning(run) else { return }
        switch result {
        case .success(let session):
            dynamicBlockCardErrors = [:]
            newDynamicBlocksError = nil
            if session.isEmpty {
                setDynamicBlockSession(nil)
                showNotice(DynamicBlockCopy.upToDate)
            } else {
                setDynamicBlockSession(session)
            }
        case .failure(let error):
            setDynamicBlockSession(nil)
            report(DynamicBlockCopy.message(for: error), origin: origin)
        }
    }

    /// Starts a planning run against the current buffer. Synchronous up to the detached work, so
    /// `isPlanningDynamicBlocks` is already true (and Apply disabled) when this returns.
    private func startDynamicBlockPlanning() -> PlanningRun {
        dynamicBlockPlanningTask?.cancel()
        dynamicBlockGeneration += 1
        isPlanningDynamicBlocks = true
        let root = workspaceRoot
        let sourcePath = todayRelativePath
        let markdown = todayText
        let calendar = calendar
        let task = Task.detached(priority: .userInitiated) { () -> Result<DynamicBlockRefreshSession, any Error> in
            Result {
                let preview = try DynamicBlockRefreshService().preview(
                    markdown: markdown,
                    sourcePath: sourcePath,
                    root: root,
                    referenceDate: Date(),
                    calendar: calendar
                )
                return DynamicBlockRefreshSession.make(preview: preview, markdown: markdown)
            }
        }
        dynamicBlockPlanningTask = task
        return (dynamicBlockGeneration, task)
    }

    /// Nil when the run was cancelled or superseded; its result must not land.
    private func finishDynamicBlockPlanning(_ run: PlanningRun) async -> Result<DynamicBlockRefreshSession, any Error>? {
        let result = await run.task.value
        guard run.generation == dynamicBlockGeneration, !run.task.isCancelled else { return nil }
        isPlanningDynamicBlocks = false
        dynamicBlockPlanningTask = nil
        return result
    }

    /// Applies exactly the patch the card showed.
    func applyDynamicBlockCard(regionHash: String) async {
        guard let patch = dynamicBlockSession?.cardPatches[regionHash] else { return }
        await applyDynamicBlockPatches([patch], origin: .card(regionHash))
    }

    /// Applies exactly the inserts the new-block popover showed.
    func insertNewDynamicBlocks() async {
        guard let blocks = dynamicBlockSession?.newBlocks, !blocks.isEmpty else { return }
        await applyDynamicBlockPatches(blocks.map(\.patch), origin: .newBlocks)
    }

    private func applyDynamicBlockPatches(_ patches: [DynamicBlockPatch], origin: DynamicBlockOrigin) async {
        guard let session = dynamicBlockSession, !isApplyingDynamicBlocks, !isPlanningDynamicBlocks else { return }
        guard !isDynamicBlockPreviewStale else {
            report(DynamicBlockCopy.stale, origin: origin)
            return
        }
        clearError(for: origin)
        let preview = session.scopedPreview(patches)

        autosaveTask?.cancel()
        isApplyingDynamicBlocks = true
        let root = workspaceRoot
        let markdown = todayText

        // Compute the applied Markdown here and record it as our own write before the disk write,
        // matching scheduleAutosave's echo-guard ordering so a watcher event racing the write is
        // recognized as an echo. The detached task runs the same deterministic apply() and
        // performs the workspace-confined write.
        let updated: String
        do {
            updated = try preview.plan.apply(to: markdown)
        } catch {
            isApplyingDynamicBlocks = false
            report(DynamicBlockCopy.message(for: error), origin: origin)
            return
        }
        recordSelfWrite(updated)

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try DynamicBlockRefreshService().apply(preview: preview, currentMarkdown: markdown, root: root)
            }
        }.value

        isApplyingDynamicBlocks = false
        switch result {
        case .success(let applied):
            // A keystroke may have landed between the snapshot above and here. Adopt the applied
            // Markdown only if the buffer still matches what was previewed; otherwise the user
            // has unsaved edits and the written disk version is a conflict to resolve, not a
            // buffer to clobber.
            if todayContentHash == preview.sourceContentHash {
                let remaining = remainingDynamicBlocks(after: origin, appliedMarkdown: applied.updatedMarkdown)
                setDynamicBlockSession(remaining)
                lastSavedText = applied.updatedMarkdown
                todayText = applied.updatedMarkdown
                reloadDynamicBlockCache()
                if remaining != nil { replanRemainingDynamicBlocks() }
            } else {
                externalDiskVersion = applied.updatedMarkdown
                hasExternalConflict = true
                setDynamicBlockSession(nil)
                // The popover closes with the session, so its failure moves to the notice.
                report(DynamicBlockCopy.changedDuringApply, origin: origin == .newBlocks ? .global : origin)
            }
            if let indexer {
                try? await indexer.indexToday()
            }
            await refreshOpenLoops()
        case .failure(let error):
            report(DynamicBlockCopy.message(for: error), origin: origin)
        }
    }

    /// The blocks still awaiting approval after `origin` was applied, rebased onto the applied
    /// Markdown. Their line indexes are now wrong, so this is display-only until
    /// `replanRemainingDynamicBlocks` replaces it; Apply stays disabled while that runs.
    private func remainingDynamicBlocks(after origin: DynamicBlockOrigin, appliedMarkdown: String) -> DynamicBlockRefreshSession? {
        guard var session = dynamicBlockSession else { return nil }
        switch origin {
        case .card(let hash): session.cardPatches[hash] = nil
        case .newBlocks: session.newBlocks = []
        case .global: return nil
        }
        guard !session.isEmpty else { return nil }
        session.preview.sourceContentHash = ContentHasher.hash(appliedMarkdown)
        return session
    }

    private func replanRemainingDynamicBlocks() {
        let run = startDynamicBlockPlanning()
        Task { [weak self] in
            guard let self, let result = await self.finishDynamicBlockPlanning(run) else { return }
            let fresh: DynamicBlockRefreshSession
            switch result {
            case .success(let session):
                fresh = session
            case .failure(let error):
                self.setDynamicBlockSession(nil)
                self.showNotice(DynamicBlockCopy.message(for: error))
                return
            }
            guard let pending = self.dynamicBlockSession else { return }
            // Read the pending set now, not at start: a card cancelled during the run stays gone.
            let narrowed = fresh.keeping(
                cards: Set(pending.cardPatches.keys),
                newBlocks: Set(pending.newBlocks.map(\.id))
            )
            self.setDynamicBlockSession(narrowed.isEmpty ? nil : narrowed)
        }
    }

    /// Cancels every pending preview and any planning run in flight. An apply already writing
    /// is left to finish, since its file write cannot be taken back.
    func dismissDynamicBlocksRefresh() {
        guard !isApplyingDynamicBlocks else { return }
        dynamicBlockPlanningTask?.cancel()
        dynamicBlockPlanningTask = nil
        dynamicBlockGeneration += 1
        isPlanningDynamicBlocks = false
        dynamicBlockCardErrors = [:]
        newDynamicBlocksError = nil
        setDynamicBlockSession(nil)
    }

    /// A card's Cancel: drops only that card's pending change and any error it shows.
    func cancelDynamicBlockCard(regionHash: String) {
        guard !isApplyingDynamicBlocks else { return }
        dynamicBlockCardErrors[regionHash] = nil
        guard var session = dynamicBlockSession, session.cardPatches[regionHash] != nil else { return }
        session.cardPatches[regionHash] = nil
        if session.isEmpty { dismissDynamicBlocksRefresh() } else { setDynamicBlockSession(session) }
    }

    /// The new-block popover's Cancel, or any close the user started: drops the inserts.
    func cancelNewDynamicBlocks() {
        guard !isApplyingDynamicBlocks else { return }
        newDynamicBlocksError = nil
        guard var session = dynamicBlockSession, !session.newBlocks.isEmpty else { return }
        session.newBlocks = []
        if session.isEmpty { dismissDynamicBlocksRefresh() } else { setDynamicBlockSession(session) }
    }

    func dismissDynamicBlockCardError(regionHash: String) {
        dynamicBlockCardErrors[regionHash] = nil
    }

    func dynamicBlockCardPreview(forRegionHash regionHash: String) -> DynamicBlockCardPreview? {
        guard let patch = dynamicBlockSession?.cardPatches[regionHash] else { return nil }
        let stale = isDynamicBlockPreviewStale
        return DynamicBlockCardPreview(
            summaryText: stale ? DynamicBlockCopy.stale : DynamicBlockCopy.summary(for: patch),
            incomingMarkdown: patch.generatedMarkdown,
            canApply: !stale && !isPlanningDynamicBlocks && !isApplyingDynamicBlocks,
            isStale: stale
        )
    }

    var canInsertNewDynamicBlocks: Bool {
        isNewDynamicBlocksPopoverPresented
            && !isDynamicBlockPreviewStale
            && !isPlanningDynamicBlocks
            && !isApplyingDynamicBlocks
    }

    /// Screen rect of the first new command line, for anchoring the new-block popover. Nil when
    /// the editor has not installed `rectForCharacterRange` or the range no longer fits.
    func newDynamicBlocksAnchorScreenRect() -> NSRect? {
        guard let range = dynamicBlockSession?.newBlocks.first?.commandLineRange,
              let rectForCharacterRange,
              NSMaxRange(range) <= (todayText as NSString).length,
              let rect = rectForCharacterRange(range),
              rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return rect
    }

    /// When the region last recorded a refresh in `.daymark/dynamic-blocks.json`, for the
    /// card header's "generated <relative time>" label. Nil when no record exists yet.
    func dynamicBlockGeneratedAt(forRegionHash regionHash: String) -> Date? {
        guard let stamp = dynamicBlockCacheRecords[regionHash]?.refreshedAt else { return nil }
        return Self.cacheDateFormatter.date(from: stamp)
    }

    private func setDynamicBlockSession(_ session: DynamicBlockRefreshSession?) {
        dynamicBlockSession = session
        updateDynamicBlockStaleness()
    }

    private func updateDynamicBlockStaleness() {
        let stale = dynamicBlockSession.map { $0.preview.sourceContentHash != todayContentHash } ?? false
        if stale != isDynamicBlockPreviewStale { isDynamicBlockPreviewStale = stale }
    }

    private func report(_ message: String, origin: DynamicBlockOrigin) {
        switch origin {
        case .global: showNotice(message)
        case .card(let hash): dynamicBlockCardErrors[hash] = message
        case .newBlocks: newDynamicBlocksError = message
        }
    }

    private func clearError(for origin: DynamicBlockOrigin) {
        switch origin {
        case .global: break
        case .card(let hash): dynamicBlockCardErrors[hash] = nil
        case .newBlocks: newDynamicBlocksError = nil
        }
    }

    private func reloadDynamicBlockCache() {
        let records = (try? DynamicBlockCacheStore().read(root: workspaceRoot)) ?? []
        let path = todayRelativePath
        dynamicBlockCacheRecords = Dictionary(
            records.filter { $0.sourcePath == path }.map { ($0.commandHash, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private static let cacheDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

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

    /// Called when the composer popover closes without Create.
    func dismissCodexTaskDraft() {
        codex.dismissComposer()
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
