import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: DesignMetrics.sidebarWidth)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appState.isContextMarginVisible {
                    ContextMarginView()
                        .frame(width: DesignMetrics.contextMarginWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(DesignTokens.canvas)

            if appState.isSlipPresented {
                SlipPanelView(isPresented: $appState.isSlipPresented)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }

            if appState.isCommandPalettePresented {
                CommandPaletteScrim(isPresented: $appState.isCommandPalettePresented)
                    .zIndex(2)
            }
        }
        .animation(DesignMotion.panel, value: appState.isContextMarginVisible)
        .animation(DesignMotion.slip, value: appState.isSlipPresented)
        .animation(DesignMotion.commandPaletteOpen, value: appState.isCommandPalettePresented)
        .task { await appState.prepareWorkspace() }
        .onChange(of: appState.todayText) { _, _ in
            appState.handleTodayTextChange()
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            if item == .openLoops {
                Task { await appState.refreshOpenLoops() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var appState = appState

        switch appState.selectedSidebarItem {
        case .openLoops:
            OpenLoopsView()
        default:
            TodayView(text: $appState.todayText)
        }
    }
}

private struct CommandPaletteScrim: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.06)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            CommandPaletteView(isPresented: $isPresented)
                .padding(.top, 96)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        }
    }
}
