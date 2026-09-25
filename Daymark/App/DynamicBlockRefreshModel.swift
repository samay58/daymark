import Foundation
import Observation
import DaymarkCore
import DaymarkIndexer

/// A dynamic block card's pending change: the one-line summary, the incoming Markdown the card
/// shows in place of its current body, and whether Apply is allowed right now.
struct DynamicBlockCardPreview: Equatable {
    var summaryText: String
    var incomingMarkdown: String
    var canApply: Bool
    var isStale: Bool
}

/// Refresh preview and approval for today's dynamic blocks: planning, the pending session that
/// cards and the new-block popover read, and the apply that writes exactly what one surface
/// showed. The app shell owns the buffer, autosave, and conflicts, and lends them through `hooks`.
@MainActor
@Observable
final class DynamicBlockRefreshModel {
    /// What the model borrows from the app shell. Closures keep the dependency one-way.
    struct Hooks {
        var sourcePath: @MainActor () -> String = { "" }
        var buffer: @MainActor () -> String = { "" }
        /// Puts applied Markdown in the buffer as the saved version.
        var adoptApplied: @MainActor (String) -> Void = { _ in }
        /// Offers written Markdown as the disk side of a conflict with unsaved edits.
        var raiseConflict: @MainActor (String) -> Void = { _ in }
        var recordSelfWrite: @MainActor (String) -> Void = { _ in }
        var cancelAutosave: @MainActor () -> Void = {}
        var showNotice: @MainActor (String) -> Void = { _ in }
        var reindexToday: @MainActor () async -> Void = {}
        var refreshOpenLoops: @MainActor () async -> Void = {}
    }

    /// Where a refresh or apply started, which decides where its failure is reported.
    private enum Origin: Equatable {
        case global
        case card(String)
        case newBlocks
    }

    private struct PlanningRun {
        var generation: Int
        var epoch: Int
        var sourcePath: String
        var task: Task<Result<DynamicBlockRefreshSession, any Error>, Never>
    }

    var workspaceRoot: WorkspaceRoot
    /// False until today's real note is in the buffer; refresh stays disabled until then.
    var isNoteLoaded = false
    @ObservationIgnored var hooks = Hooks()

    /// The pending refresh preview, if any. Cards and the new-block popover read their own part.
    private(set) var session: DynamicBlockRefreshSession?
    /// Flips once when the buffer first diverges from the previewed Markdown, so card bodies
    /// observe one bool instead of the buffer.
    private(set) var isPreviewStale = false
    private(set) var isPlanning = false
    private(set) var isApplying = false
    /// Failures scoped to one card, keyed by region hash, shown in that card's footer.
    private(set) var cardErrors: [String: String] = [:]
    /// Failure shown inside the new-block popover.
    private(set) var newBlocksError: String?
    /// Whether the buffer has a known `/daymark` command, refreshed shortly after typing stops.
    private(set) var noteHasCommand = false

    private let calendar: Calendar
    /// Every planning run bumps this; a result from an older run (cancelled or superseded) is
    /// ignored, since the detached planner itself cannot be interrupted.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var planningTask: Task<Result<DynamicBlockRefreshSession, any Error>, Never>?
    /// Bumped when the workspace is about to switch. An apply still writing to the old note
    /// compares against it on return and drops its result rather than touching the new buffer.
    @ObservationIgnored private var workspaceEpoch = 0
    @ObservationIgnored private var commandDetectionTask: Task<Void, Never>?
    /// Cache records for today's note, keyed by command hash, backing each card's
    /// "generated <relative time>" label. Reloaded after workspace load and after apply.
    private var cacheRecords: [String: DynamicBlockCacheRecord] = [:]

    private static let commandDetectionDelay: Duration = .milliseconds(150)

    init(workspaceRoot: WorkspaceRoot, calendar: Calendar) {
        self.workspaceRoot = workspaceRoot
        self.calendar = calendar
    }

    // MARK: - Derived state

    var canRefresh: Bool { isNoteLoaded && noteHasCommand }

    var isNewBlocksPopoverPresented: Bool { !(session?.newBlocks.isEmpty ?? true) }

    var canInsertNewBlocks: Bool {
        isNewBlocksPopoverPresented && !isPreviewStale && !isPlanning && !isApplying
    }

    /// The first new command line, for anchoring the new-block popover.
    var newBlocksAnchorRange: NSRange? { session?.newBlocks.first?.commandLineRange }

    func cardPreview(forRegionHash regionHash: String) -> DynamicBlockCardPreview? {
        guard let patch = session?.cardPatches[regionHash] else { return nil }
        let stale = isPreviewStale
        return DynamicBlockCardPreview(
            summaryText: stale ? DynamicBlockCopy.stale : DynamicBlockCopy.summary(for: patch),
            incomingMarkdown: patch.generatedMarkdown,
            canApply: !stale && !isPlanning && !isApplying,
            isStale: stale
        )
    }

    /// When the region last recorded a refresh in `.daymark/dynamic-blocks.json`, for the card
    /// header's "generated <relative time>" label. A region's begin marker carries the command
    /// hash of the refresh that wrote it, which is the key that refresh recorded, so the region
    /// hash finds its own record even after the command line was edited.
    func generatedAt(forRegionHash regionHash: String) -> Date? {
        guard let stamp = cacheRecords[regionHash]?.refreshedAt else { return nil }
        return Self.cacheDateFormatter.date(from: stamp)
    }

    // MARK: - Buffer changes

    /// Called on every buffer change, so it does no whole-note work: while a preview is pending
    /// it compares against the previewed text (a length check first, then bytes only when the
    /// lengths match, as when an undo returns to the previewed note), and the command scan is
    /// debounced off the main actor.
    func bufferDidChange() {
        if let session {
            let stale = !Self.sameBytes(hooks.buffer(), session.sourceMarkdown)
            if stale != isPreviewStale { isPreviewStale = stale }
        }
        scheduleCommandDetection()
    }

    /// Byte equality, not Swift's canonical equivalence: the apply service checks a byte hash,
    /// so "not stale" must mean the same bytes.
    private static func sameBytes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.count == rhs.utf8.count && lhs.utf8.elementsEqual(rhs.utf8)
    }

    private func scheduleCommandDetection() {
        commandDetectionTask?.cancel()
        commandDetectionTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commandDetectionDelay)
            guard !Task.isCancelled, let self else { return }
            let text = self.hooks.buffer()
            let found = await Task.detached(priority: .utility) {
                DynamicBlockParser().containsKnownCommand(in: text)
            }.value
            guard !Task.isCancelled, found != self.noteHasCommand else { return }
            self.noteHasCommand = found
        }
    }

    // MARK: - Preview

    /// Menu, palette, and shortcut refresh. Failures and "nothing to do" go to the notice.
    func preview() async {
        await preview(origin: .global)
    }

    /// A card's own refresh button. Failures show in that card's footer.
    func preview(fromCard regionHash: String) async {
        await preview(origin: .card(regionHash))
    }

    private func preview(origin: Origin) async {
        guard !isApplying else { return }
        guard isNoteLoaded else {
            report(DynamicBlockCopy.notLoaded, origin: origin)
            return
        }
        // Checked now rather than read from `noteHasCommand`, which trails typing slightly.
        guard DynamicBlockParser().containsKnownCommand(in: hooks.buffer()) else {
            setSession(nil)
            hooks.showNotice(DynamicBlockCopy.noCommands)
            return
        }
        if case .card(let hash) = origin { cardErrors[hash] = nil }

        let run = startPlanning()
        guard let result = await finishPlanning(run) else { return }
        switch result {
        case .success(let session):
            cardErrors = [:]
            newBlocksError = nil
            if session.isEmpty {
                setSession(nil)
                hooks.showNotice(DynamicBlockCopy.upToDate)
            } else {
                setSession(session)
            }
        case .failure(let error):
            setSession(nil)
            report(DynamicBlockCopy.message(for: error), origin: origin)
        }
    }

    /// Starts a planning run against the current buffer. Synchronous up to the detached work, so
    /// `isPlanning` is already true (and Apply disabled) when this returns.
    private func startPlanning() -> PlanningRun {
        planningTask?.cancel()
        generation += 1
        isPlanning = true
        let root = workspaceRoot
        let sourcePath = hooks.sourcePath()
        let markdown = hooks.buffer()
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
        planningTask = task
        return PlanningRun(generation: generation, epoch: workspaceEpoch, sourcePath: sourcePath, task: task)
    }

    /// Nil when the run was cancelled or superseded, or planned a note that is no longer today's;
    /// its result must not land.
    private func finishPlanning(_ run: PlanningRun) async -> Result<DynamicBlockRefreshSession, any Error>? {
        let result = await run.task.value
        guard run.generation == generation, !run.task.isCancelled else { return nil }
        guard run.epoch == workspaceEpoch, run.sourcePath == hooks.sourcePath() else {
            dismiss()
            return nil
        }
        isPlanning = false
        planningTask = nil
        return result
    }

    // MARK: - Apply

    /// Applies exactly the patch the card showed.
    func applyCard(regionHash: String) async {
        guard let patch = session?.cardPatches[regionHash] else { return }
        await apply([patch], origin: .card(regionHash))
    }

    /// Applies exactly the inserts the new-block popover showed.
    func insertNewBlocks() async {
        guard let blocks = session?.newBlocks, !blocks.isEmpty else { return }
        await apply(blocks.map(\.patch), origin: .newBlocks)
    }

    private func apply(_ patches: [DynamicBlockPatch], origin: Origin) async {
        guard let session, isNoteLoaded, !isApplying, !isPlanning else { return }
        guard !isPreviewStale else {
            report(DynamicBlockCopy.stale, origin: origin)
            return
        }
        clearError(for: origin)
        let preview = session.scopedPreview(patches)
        let epoch = workspaceEpoch
        let root = workspaceRoot
        let markdown = hooks.buffer()

        hooks.cancelAutosave()
        isApplying = true

        // Compute the applied Markdown here and record it as our own write before the disk write,
        // matching autosave's echo-guard ordering so a watcher event racing the write is
        // recognized as an echo. The detached task runs the same deterministic apply() and
        // performs the workspace-confined write.
        let updated: String
        do {
            updated = try preview.plan.apply(to: markdown)
        } catch {
            isApplying = false
            report(DynamicBlockCopy.message(for: error), origin: origin)
            return
        }
        hooks.recordSelfWrite(updated)

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try DynamicBlockRefreshService().apply(preview: preview, currentMarkdown: markdown, root: root)
            }
        }.value

        isApplying = false
        // The write landed in a note that is no longer on screen (the workspace switched or the
        // day rolled over). It is correct where it is; the buffer now holds a different note.
        guard epoch == workspaceEpoch, preview.sourcePath == hooks.sourcePath() else {
            dismiss()
            return
        }
        switch result {
        case .success(let applied):
            // A keystroke may have landed between the snapshot above and here. Adopt the applied
            // Markdown only if the buffer still matches what was previewed; otherwise the user
            // has unsaved edits and the written disk version is a conflict to resolve, not a
            // buffer to clobber.
            if hooks.buffer() == markdown {
                let remaining = remainingSession(after: origin, appliedMarkdown: applied.updatedMarkdown)
                hooks.adoptApplied(applied.updatedMarkdown)
                setSession(remaining)
                reloadCache()
                if remaining != nil { replanRemaining() }
            } else {
                hooks.raiseConflict(applied.updatedMarkdown)
                setSession(nil)
                // The popover closes with the session, so its failure moves to the notice.
                report(DynamicBlockCopy.changedDuringApply, origin: origin == .newBlocks ? .global : origin)
            }
            await hooks.reindexToday()
            await hooks.refreshOpenLoops()
        case .failure(let error):
            report(DynamicBlockCopy.message(for: error), origin: origin)
        }
    }

    /// The blocks still awaiting approval after `origin` was applied, rebased onto the applied
    /// Markdown. Their line indexes are now wrong, so this is display-only until
    /// `replanRemaining` replaces it; Apply stays disabled while that runs.
    private func remainingSession(after origin: Origin, appliedMarkdown: String) -> DynamicBlockRefreshSession? {
        guard var session else { return nil }
        switch origin {
        case .card(let hash): session.cardPatches[hash] = nil
        case .newBlocks: session.newBlocks = []
        case .global: return nil
        }
        guard !session.isEmpty else { return nil }
        session.sourceMarkdown = appliedMarkdown
        session.preview.sourceContentHash = ContentHasher.hash(appliedMarkdown)
        return session
    }

    private func replanRemaining() {
        let run = startPlanning()
        Task { [weak self] in
            guard let self, let result = await self.finishPlanning(run) else { return }
            let fresh: DynamicBlockRefreshSession
            switch result {
            case .success(let session):
                fresh = session
            case .failure(let error):
                self.setSession(nil)
                self.hooks.showNotice(DynamicBlockCopy.message(for: error))
                return
            }
            guard let pending = self.session else { return }
            // Read the pending set now, not at start: a card cancelled during the run stays gone.
            let narrowed = fresh.keeping(
                cards: Set(pending.cardPatches.keys),
                newBlocks: Set(pending.newBlocks.map(\.id))
            )
            self.setSession(narrowed.isEmpty ? nil : narrowed)
        }
    }

    // MARK: - Cancel and dismiss

    /// Cancels every pending preview and any planning run in flight. An apply already writing
    /// is left to finish, since its file write cannot be taken back.
    func dismiss() {
        guard !isApplying else { return }
        cancelPlanning()
        cardErrors = [:]
        newBlocksError = nil
        setSession(nil)
    }

    /// Drops everything planned against the current workspace, including while an apply is
    /// writing: that apply sees the bumped epoch when it returns and discards its result.
    func workspaceWillChange() {
        workspaceEpoch += 1
        // Until the new note loads, the buffer still holds the old workspace's note.
        isNoteLoaded = false
        cancelPlanning()
        cardErrors = [:]
        newBlocksError = nil
        cacheRecords = [:]
        setSession(nil)
    }

    /// A card's Cancel: drops only that card's pending change and any error it shows.
    func cancelCard(regionHash: String) {
        guard !isApplying else { return }
        cardErrors[regionHash] = nil
        guard var session, session.cardPatches[regionHash] != nil else { return }
        session.cardPatches[regionHash] = nil
        if session.isEmpty { dismiss() } else { setSession(session) }
    }

    /// The new-block popover's Cancel, or any close the user started: drops the inserts.
    func cancelNewBlocks() {
        guard !isApplying else { return }
        newBlocksError = nil
        guard var session, !session.newBlocks.isEmpty else { return }
        session.newBlocks = []
        if session.isEmpty { dismiss() } else { setSession(session) }
    }

    func dismissCardError(regionHash: String) {
        cardErrors[regionHash] = nil
    }

    private func cancelPlanning() {
        planningTask?.cancel()
        planningTask = nil
        generation += 1
        isPlanning = false
    }

    // MARK: - State

    private func setSession(_ session: DynamicBlockRefreshSession?) {
        self.session = session
        let stale = session.map { !Self.sameBytes(hooks.buffer(), $0.sourceMarkdown) } ?? false
        if stale != isPreviewStale { isPreviewStale = stale }
    }

    private func report(_ message: String, origin: Origin) {
        switch origin {
        case .global: hooks.showNotice(message)
        case .card(let hash): cardErrors[hash] = message
        case .newBlocks: newBlocksError = message
        }
    }

    private func clearError(for origin: Origin) {
        switch origin {
        case .global: break
        case .card(let hash): cardErrors[hash] = nil
        case .newBlocks: newBlocksError = nil
        }
    }

    func reloadCache() {
        let records = (try? DynamicBlockCacheStore().read(root: workspaceRoot)) ?? []
        let path = hooks.sourcePath()
        cacheRecords = Dictionary(
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
}
