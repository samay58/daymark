import SwiftUI

/// SwiftUI entry point for the AppKit editing surface. Width and padding are owned by the
/// host view so the writing column can align with the day header.
struct DaymarkEditorView: View {
    @Binding var text: String

    var body: some View {
        NSTextViewRepresentable(text: $text)
    }
}
