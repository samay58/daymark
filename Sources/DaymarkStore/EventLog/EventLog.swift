import Foundation

public struct EventLog {
    public init() {}

    public func knownEventTypes() -> [String] {
        [
            "note_created",
            "note_edited",
            "task_created",
            "task_completed",
            "task_rolled_over",
            "slip_captured",
            "slip_promoted",
            "codex_task_created",
            "dynamic_block_evaluated",
            "source_linked",
            "agent_preview_created",
            "external_file_changed",
            "doctor_check_failed"
        ]
    }
}
