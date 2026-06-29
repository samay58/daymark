import Foundation

struct SelectionModel: Equatable {
    var selectedText: String
    var sourcePath: String?
    var selectedRange: NSRange
    var cursorLocation: Int

    init(
        selectedText: String = "",
        sourcePath: String? = nil,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        cursorLocation: Int = 0
    ) {
        self.selectedText = selectedText
        self.sourcePath = sourcePath
        self.selectedRange = selectedRange
        self.cursorLocation = cursorLocation
    }
}
