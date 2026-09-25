import Foundation
import DaymarkCore
import DaymarkIndexer

extension DynamicBlockCommand {
    /// The title a card and the new-block popover show for this command.
    var blockTitle: String {
        switch self {
        case .openLoops: return "Open Loops"
        case .sourceList: return "Sources"
        case .codexContext: return "Codex Context"
        case .weeklyReview: return "Weekly Review"
        }
    }
}

/// A `/daymark` line with no generated region yet, and the insert that would create one.
struct NewDynamicBlock: Equatable, Identifiable, Sendable {
    var patch: DynamicBlockPatch

    var id: String { patch.commandHash }
    var title: String { patch.command.blockTitle }
    /// The command line's range in the Markdown the preview was planned from.
    var commandLineRange: NSRange { patch.commandLineRange }
}

/// One refresh preview, split by where each change is approved: replacements on the card whose
/// region they rewrite, inserts in the new-block popover. Only patches that would change the
/// note are kept, so an unchanged block never shows Apply.
struct DynamicBlockRefreshSession: Equatable, Sendable {
    var preview: DynamicBlockRefreshPreview
    /// The buffer the preview was planned from. Staleness is a string comparison against it, so
    /// the keystroke path never hashes the note.
    var sourceMarkdown: String
    /// Keyed by the hash in the existing region's begin marker, which is what a card knows. That
    /// differs from `patch.commandHash` once the command line has been edited.
    var cardPatches: [String: DynamicBlockPatch]
    var newBlocks: [NewDynamicBlock]

    var isEmpty: Bool { cardPatches.isEmpty && newBlocks.isEmpty }

    static func make(preview: DynamicBlockRefreshPreview, markdown: String) -> DynamicBlockRefreshSession {
        var cardPatches: [String: DynamicBlockPatch] = [:]
        var newBlocks: [NewDynamicBlock] = []
        for patch in preview.plan.patches where patch.changesMarkdown {
            switch patch.operation {
            case .insert:
                newBlocks.append(NewDynamicBlock(patch: patch))
            case .replacement:
                guard let regionHash = patch.existingRegionHash else { continue }
                cardPatches[regionHash] = patch
            }
        }
        return DynamicBlockRefreshSession(
            preview: preview,
            sourceMarkdown: markdown,
            cardPatches: cardPatches,
            newBlocks: newBlocks
        )
    }

    /// A copy that previews only `patches`, for applying exactly what one surface showed.
    /// `DynamicBlockPatchPlan.apply` uses each patch's own line indexes, so a subset of a plan
    /// applies correctly against the same source Markdown.
    func scopedPreview(_ patches: [DynamicBlockPatch]) -> DynamicBlockRefreshPreview {
        var scoped = preview
        scoped.plan.patches = patches
        return scoped
    }

    /// Narrows a fresh session to the blocks that were still waiting for approval before it was
    /// planned, so applying one card never surfaces previews the user already dismissed.
    func keeping(cards cardHashes: Set<String>, newBlocks newBlockIDs: Set<String>) -> DynamicBlockRefreshSession {
        var narrowed = self
        narrowed.cardPatches = cardPatches.filter { cardHashes.contains($0.key) }
        narrowed.newBlocks = newBlocks.filter { newBlockIDs.contains($0.id) }
        return narrowed
    }
}

enum DynamicBlockCopy {
    static let stale = "Note changed; preview again"
    static let upToDate = "Dynamic blocks are up to date"
    static let noCommands = "No dynamic blocks in this note"
    static let notLoaded = "Today's note is still loading"
    static let changedDuringApply = "Note changed during refresh; resolve the conflict to keep it"

    static func summary(for patch: DynamicBlockPatch) -> String {
        let count = lineCount(patch.generatedMarkdown)
        let lines = "\(count) line\(count == 1 ? "" : "s")"
        return patch.operation == .insert ? "Will add \(lines)" : "Will replace with \(lines)"
    }

    static func lineCount(_ markdown: String) -> Int {
        let trimmed = markdown.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: "\n").count
    }

    static func message(for error: Error) -> String {
        if let error = error as? DynamicBlockError {
            switch error {
            case .unsupportedCommand(let name, let line):
                return "Unknown block \u{201C}\(name)\u{201D} on line \(line)"
            case .unsupportedRenderer(let command):
                return "\(command.blockTitle) is not available yet"
            case .unsupportedArgument(let command, let argument):
                return "\(command.blockTitle) does not take \u{201C}\(argument)\u{201D}"
            case .missingGeneratedRegionEnd(let line):
                return "The block on line \(line) is missing its end marker"
            }
        }
        if let error = error as? DynamicBlockRefreshError {
            switch error {
            case .stalePreview: return stale
            case .sourceOutsideWorkspace: return "This note is outside the workspace"
            }
        }
        return "Could not refresh dynamic blocks"
    }
}
