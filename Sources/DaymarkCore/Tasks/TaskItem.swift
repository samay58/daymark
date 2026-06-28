import Foundation

public struct TaskItem: Equatable, Sendable {
    public enum Status: String, Sendable {
        case open
        case completed
    }

    public var title: String
    public var status: Status
    public var tags: [String]
    public var mentions: [String]

    public init(title: String, status: Status, tags: [String] = [], mentions: [String] = []) {
        self.title = title
        self.status = status
        self.tags = tags
        self.mentions = mentions
    }
}
