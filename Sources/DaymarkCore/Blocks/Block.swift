import Foundation

public struct Block: Equatable, Sendable {
    public var id: String
    public var markdown: String
    public var lineStart: Int
    public var lineEnd: Int

    public init(id: String, markdown: String, lineStart: Int, lineEnd: Int) {
        self.id = id
        self.markdown = markdown
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}
