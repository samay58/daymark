import SwiftUI
import AppKit

struct TodayView: View {
    @Binding var text: String
    @Environment(AppState.self) private var appState
    @State private var isScrolled = false
    @State private var headerHeight: CGFloat = 0
    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if appState.hasExternalConflict {
                conflictBanner
            }
            documentBody
        }
        .background(DesignTokens.canvas)
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        ) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }

    private var documentBody: some View {
        ZStack(alignment: .top) {
            editorColumn
            headerBand
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var editorColumn: some View {
        @Bindable var appState = appState
        return DaymarkEditorView(
            text: $text,
            selection: $appState.editorSelection,
            sourcePath: appState.todayRelativePath
        )
            .background(
                ScrollChromeAdapter(topInset: headerHeight + 14) { scrolled in
                    if isScrolled != scrolled {
                        withAnimation(DesignMotion.hover) { isScrolled = scrolled }
                    }
                }
            )
            .frame(maxWidth: DesignMetrics.editorMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
    }

    // The day header, tile row plus brief strip, floats over the editor column as a
    // material band. The editor's own scroll content inset (ScrollChromeAdapter) reserves
    // this much vertical space at rest, and note content passes underneath, blurred by the
    // material, once scrolled.
    private var headerBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                DateTile(day: Self.dayNumber(from: Date()))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.monthFormatter.string(from: Date()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(Self.weekdayFormatter.string(from: Date()))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    ToolbarIcon(symbol: "square.and.pencil", label: "Capture to Slip") { appState.isSlipPresented = true }
                    ToolbarIcon(symbol: "magnifyingglass", label: "Search") { appState.showCommandPalette(prefill: nil) }
                    ToolbarIcon(symbol: "circle.dashed", label: "Open Loops") { appState.toggleOpenLoopsOverlay() }
                }
            }

            briefStrip
        }
        // Anchor for the new-block popover. It points at the command line when the editor can
        // report one, and at this header otherwise.
        .background(NewDynamicBlocksPopoverHost(appState: appState).allowsHitTesting(false))
        .padding(.horizontal, 40)
        .padding(.top, DesignMetrics.editorTopPadding)
        .padding(.bottom, 14)
        .background(headerMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.hairline)
                .frame(height: 1)
                .opacity(isScrolled ? 1 : 0)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
    }

    @ViewBuilder
    private var headerMaterial: some View {
        if reduceTransparency {
            DesignTokens.canvas
        } else {
            ZStack {
                HeaderVisualEffectView()
                DesignTokens.canvas.opacity(DesignTokens.glassTintOpacity)
            }
        }
    }

    /// A notice replaces the strip's text for a few seconds, then the strip returns.
    private var briefStrip: some View {
        BriefStripText(
            text: appState.notice ?? Self.briefStripText(
                carriedOver: appState.rolledOverCount,
                openLoops: appState.openLoopCount,
                isSaving: appState.isSaving
            )
        )
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: appState.notice)
        .contentShape(Rectangle())
        .onTapGesture { appState.toggleOpenLoopsOverlay() }
        .onChange(of: appState.notice) { _, notice in
            guard let notice else { return }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: notice,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
        }
    }

    static func briefStripText(carriedOver: Int, openLoops: Int, isSaving: Bool) -> String {
        var segments: [String] = []
        if carriedOver > 0 {
            segments.append("\(carriedOver) carried over")
        }
        if openLoops > 0 {
            segments.append("\(openLoops) open \(openLoops == 1 ? "loop" : "loops")")
        }
        segments.append(isSaving ? "Saving" : "Saved")
        return segments.joined(separator: " · ")
    }

    private var conflictBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.warning)
            Text("This note changed on disk while you had unsaved edits.")
                .font(DesignType.metadata)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Button("Keep mine") { appState.keepLocalVersion() }
                .buttonStyle(QuietButtonStyle())
            Button("Use disk version") { appState.acceptExternalChange() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .padding(.horizontal, 40)
        .padding(.top, 16)
    }

    private static func dayNumber(from date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Warm within-window material for the day header band. Hidden entirely when Reduce
// Transparency is on; the caller falls back to an opaque canvas fill in that case.
private struct HeaderVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .headerView
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Gives the editor's NSScrollView a top content inset equal to the floating header's height,
// and reports scroll position back to the header for the scroll-edge hairline. It finds the
// scroll view by walking the window's hierarchy and sets only standard NSScrollView
// properties, the way a host reacts to a floating toolbar.
private struct ScrollChromeAdapter: NSViewRepresentable {
    var topInset: CGFloat
    var onScrolledChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        anchor.translatesAutoresizingMaskIntoConstraints = true
        DispatchQueue.main.async {
            context.coordinator.attach(from: anchor)
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.topInset = topInset
        context.coordinator.onScrolledChange = onScrolledChange
        // The one-shot async attach in makeNSView can run before the anchor is in a window.
        // attach is idempotent, so retrying here lands it once the view is in the hierarchy.
        context.coordinator.attach(from: nsView)
        context.coordinator.applyInset()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var topInset: CGFloat = 0
        var onScrolledChange: (Bool) -> Void = { _ in }
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        func attach(from anchor: NSView) {
            guard scrollView == nil, let root = anchor.window?.contentView else { return }
            guard let found = Self.findEditorScrollView(in: root) else {
                #if DEBUG
                NSLog("[Daymark] scroll chrome adapter: editor scroll view not found yet")
                #endif
                return
            }
            scrollView = found
            found.automaticallyAdjustsContentInsets = false
            applyInset()
            #if DEBUG
            NSLog("[Daymark] scroll chrome adapter: attached, top inset %.1f", topInset)
            #endif

            found.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: found.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.reportScrollState()
            }
            reportScrollState()
        }

        func applyInset() {
            guard let scrollView else { return }
            guard scrollView.contentInsets.top != topInset else { return }
            scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
            #if DEBUG
            NSLog("[Daymark] scroll chrome adapter: content top inset now %.1f", topInset)
            #endif
        }

        private func reportScrollState() {
            guard let scrollView else { return }
            onScrolledChange(scrollView.contentView.bounds.origin.y > 0.5)
        }

        private static func findEditorScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView, scrollView.documentView is LiveTextView {
                return scrollView
            }
            for subview in view.subviews {
                if let found = findEditorScrollView(in: subview) {
                    return found
                }
            }
            return nil
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }
    }
}

private struct BriefStripText: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovering ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .onHover { hovering in
                withAnimation(DesignMotion.hover) { isHovering = hovering }
            }
    }
}

private struct ToolbarIcon: View {
    let symbol: String
    let label: String
    var action: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isHovering ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .frame(width: 26, height: 26)
                .background(isHovering ? Color.black.opacity(0.04) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(DesignMotion.hover) { isHovering = hovering }
        }
    }
}
