import SwiftUI

@MainActor
final class WindowManager {
    func focusToday() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
