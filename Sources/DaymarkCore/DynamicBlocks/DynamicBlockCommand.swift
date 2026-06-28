import Foundation

public enum DynamicBlockCommand: String, CaseIterable, Sendable {
    case openLoops = "open-loops"
    case todayCalendar = "today-calendar"
    case sourceList = "source-list"
    case codexContext = "codex-context"
}
