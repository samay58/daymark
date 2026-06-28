import Foundation
import DaymarkCore

public struct PreviewBuilder {
    public init() {}

    public func codexTaskPreview(title: String, selectedText: String, sourcePath: String) -> CodexTaskDraft {
        CodexTaskDraft(
            title: title,
            goal: selectedText,
            sourcePath: sourcePath,
            acceptanceCriteria: [
                "Generated task is human-readable",
                "Source note is linked",
                "Acceptance criteria are explicit"
            ]
        )
    }
}
