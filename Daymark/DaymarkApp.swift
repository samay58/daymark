import SwiftUI
import AppKit

@main
struct DaymarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(
                    minWidth: DesignMetrics.minWindowWidth,
                    minHeight: DesignMetrics.minWindowHeight
                )
                .preferredColorScheme(.light)
        }
        .defaultSize(width: DesignMetrics.windowWidth, height: DesignMetrics.windowHeight)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MenuCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(.light)
        }
    }
}

// Running from SwiftPM (no app bundle) leaves the process without a regular activation
// policy, so the window can launch unfocused or behind other apps. Promote it on launch
// so `swift run Daymark` opens a focused Today window. The real bundle arrives with Milestone 1.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
