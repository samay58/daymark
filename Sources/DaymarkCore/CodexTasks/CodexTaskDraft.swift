import Foundation

public struct CodexTaskDraft: Equatable, Sendable {
    public var title: String
    public var goal: String
    public var sourcePath: String
    public var acceptanceCriteria: [String]

    public init(title: String, goal: String, sourcePath: String, acceptanceCriteria: [String]) {
        self.title = title
        self.goal = goal
        self.sourcePath = sourcePath
        self.acceptanceCriteria = acceptanceCriteria
    }

    public func markdown() -> String {
        let criteria = acceptanceCriteria.map { "- [ ] \($0)" }.joined(separator: "\n")
        return """
        # \(title)

        ## Goal

        \(goal)

        ## Source

        \(sourcePath)

        ## Acceptance Criteria

        \(criteria)
        """
    }
}
