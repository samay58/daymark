import Foundation
import Observation
import DaymarkCore
import DaymarkAgents

/// A Codex task file that has been written, paired with the exact draft it came from, so the
/// path and the draft a context bundle is built from can never disagree.
struct CreatedCodexTask: Equatable {
    var relativePath: String
    var draft: CodexTaskDraft
}

/// The Codex handoff: the composer popover and the receipt card. Each surface owns exactly one
/// value, so a new draft can never strand the receipt with a missing task (the receipt carries
/// its own created task), and the popover is open exactly while a composer exists.
@MainActor
@Observable
final class CodexFlowModel {
    struct Composer: Equatable {
        var draft: CodexTaskDraft
        var error: String?
        /// The existing-path set and date the draft's file name was derived from. Edits
        /// re-derive the name against the same basis so the suggested path stays stable.
        var pathBasis: Set<String>
        var dateBasis: Date
    }

    enum BundleState: Equatable {
        case collapsed
        case previewing(CodexContextBundle, error: String?)
        case written(CodexContextBundle)
    }

    struct Receipt: Equatable {
        var task: CreatedCodexTask
        var bundle: BundleState
    }

    var workspaceRoot: WorkspaceRoot
    private(set) var composer: Composer?
    private(set) var receipt: Receipt?

    init(workspaceRoot: WorkspaceRoot) {
        self.workspaceRoot = workspaceRoot
    }

    var canCreateTask: Bool { composer?.draft.isWritable ?? false }

    var canCreateBundle: Bool {
        guard case .previewing(let bundle, _)? = receipt?.bundle else { return false }
        return bundle.isWritable
    }

    // MARK: - Composer

    /// Builds a draft from the selection (or the block under the caret) and opens the composer.
    /// Returns false when there is nothing to build from; the caller reports that.
    @discardableResult
    func startDraft(text: String, selection: SelectionModel, fallbackSourcePath: String) -> Bool {
        do {
            let source = try SourceSelector().select(
                text: text,
                selectedRange: selection.selectedRange,
                cursorLocation: selection.cursorLocation,
                sourcePath: selection.sourcePath ?? fallbackSourcePath
            )
            let existingPaths = workspaceRoot.existingMarkdownRelativePaths(under: "specs/tasks")
            let date = Date()
            let draft = try PreviewBuilder().codexTaskPreview(
                source: source,
                date: date,
                existingRelativePaths: existingPaths
            )
            composer = Composer(draft: draft, error: nil, pathBasis: existingPaths, dateBasis: date)
            return true
        } catch {
            composer = nil
            return false
        }
    }

    func updateTitle(_ title: String) { editFields(title: title) }
    func updateGoal(_ goal: String) { editFields(goal: goal) }
    func updateConstraints(_ text: String) { editFields(constraints: Self.lines(from: text)) }
    func updateAcceptanceCriteria(_ text: String) { editFields(acceptanceCriteria: Self.lines(from: text)) }

    /// A nil field keeps the draft's current value. Swift default arguments cannot reference the
    /// runtime draft, so each unset field resolves against it here.
    private func editFields(
        title: String? = nil,
        goal: String? = nil,
        constraints: [String]? = nil,
        acceptanceCriteria: [String]? = nil
    ) {
        guard var composer else { return }
        let draft = composer.draft
        composer.draft = draft.withEditedFields(
            title: title ?? draft.title,
            goal: goal ?? draft.goal,
            constraints: constraints ?? draft.constraints,
            acceptanceCriteria: acceptanceCriteria ?? draft.acceptanceCriteria,
            date: composer.dateBasis,
            existingRelativePaths: composer.pathBasis
        )
        composer.error = nil
        self.composer = composer
    }

    /// Writes the task file, closes the composer, and replaces any previous receipt.
    func createTask() {
        guard var composer else { return }
        do {
            let result = try CodexTaskFileWriter().write(composer.draft, root: workspaceRoot)
            let written = composer.draft.withSuggestedFilePath(result.relativePath)
            receipt = Receipt(task: CreatedCodexTask(relativePath: result.relativePath, draft: written), bundle: .collapsed)
            self.composer = nil
        } catch CodexTaskFileWriter.Error.blankDraft {
            composer.error = "Add a title and goal first"
            self.composer = composer
        } catch CodexTaskFileWriter.Error.invalidPath {
            composer.error = "Task files must stay under specs/tasks"
            self.composer = composer
        } catch {
            composer.error = "Could not create the task file"
            self.composer = composer
        }
    }

    func dismissComposer() {
        composer = nil
    }

    // MARK: - Receipt and context bundle

    /// Expands the receipt into the bundle preview, built from the exact draft the receipt's
    /// task file was written from.
    func expandReceiptToBundle() {
        guard var receipt else { return }
        let existingPaths = workspaceRoot.existingMarkdownRelativePaths(under: "artifacts/context-bundles")
        let bundle = CodexContextBundle.from(
            draft: receipt.task.draft,
            taskRelativePath: receipt.task.relativePath,
            date: Date(),
            existingRelativePaths: existingPaths
        )
        receipt.bundle = .previewing(bundle, error: nil)
        self.receipt = receipt
    }

    func createBundle() {
        guard var receipt, case .previewing(let bundle, _) = receipt.bundle else { return }
        do {
            let result = try CodexContextBundleWriter().write(bundle, root: workspaceRoot)
            receipt.bundle = .written(bundle.withSuggestedFilePath(result.relativePath))
        } catch CodexContextBundleWriter.Error.blankBundle {
            receipt.bundle = .previewing(bundle, error: "The bundle needs a task, goal, source, and excerpt")
        } catch CodexContextBundleWriter.Error.invalidPath {
            receipt.bundle = .previewing(bundle, error: "Bundles must stay under artifacts/context-bundles")
        } catch {
            receipt.bundle = .previewing(bundle, error: "Could not create the context bundle")
        }
        self.receipt = receipt
    }

    func collapseBundle() {
        guard var receipt else { return }
        receipt.bundle = .collapsed
        self.receipt = receipt
    }

    func dismissReceipt() {
        receipt = nil
    }

    private static func lines(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet.newlines)
    }
}
