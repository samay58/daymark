import Foundation

public struct TaskParser {
    public init() {}

    public func parse(markdown: String) -> [TaskItem] {
        markdown
            .split(separator: "\n")
            .compactMap(parseLine)
    }

    private func parseLine(_ line: Substring) -> TaskItem? {
        let text = line.trimmingCharacters(in: .whitespaces)
        let openPrefix = "- [ ] "
        let donePrefix = "- [x] "

        let status: TaskItem.Status
        let body: String

        if text.hasPrefix(openPrefix) {
            status = .open
            body = String(text.dropFirst(openPrefix.count))
        } else if text.hasPrefix(donePrefix) {
            status = .completed
            body = String(text.dropFirst(donePrefix.count))
        } else {
            return nil
        }

        return TaskItem(
            title: body,
            status: status,
            tags: body.split(separator: " ").filter { $0.hasPrefix("#") }.map(String.init),
            mentions: body.split(separator: " ").filter { $0.hasPrefix("@") }.map(String.init)
        )
    }
}
