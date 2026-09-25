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
// policy, so the window can launch unfocused or behind other apps. Promoting it on launch
// gives `swift run DaymarkApp` a focused Today window; the installed bundle is unaffected.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didEnforceLaunchFrame = false
    private var keyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyAppIcon()
        NSApp.activate(ignoringOtherApps: true)

        // The window may not exist yet when this fires (WindowGroup creates it lazily,
        // and macOS restores any prior saved frame before it becomes key). Race two
        // triggers and let whichever fires first run the one-time enforcement.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.enforceLaunchFrame(on: window)
        }

        DispatchQueue.main.async { [weak self] in
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            self?.enforceLaunchFrame(on: window)
        }
    }

    // The window never opens maximized or zoomed. If the restored frame covers 90 percent
    // or more of the active screen's visible frame in either dimension, reset it to the
    // default size, centered. Runs once; a later user-triggered zoom is untouched.
    private func enforceLaunchFrame(on window: NSWindow) {
        guard !didEnforceLaunchFrame else { return }
        defer {
            didEnforceLaunchFrame = true
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
                self.keyObserver = nil
            }
        }

        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        let coversWidth = frame.width >= visible.width * 0.9
        let coversHeight = frame.height >= visible.height * 0.9
        guard coversWidth || coversHeight else { return }

        let width = DesignMetrics.windowWidth
        let height = DesignMetrics.windowHeight
        let originX = visible.origin.x + (visible.width - width) / 2
        let originY = visible.origin.y + (visible.height - height) / 2
        window.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
    }

    // `swift run` has no bundle Info.plist to name the icon, so set it from the AppIcon.icns resource.
    private func applyAppIcon() {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = icon
    }
}
