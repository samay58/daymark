import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .top) {
            TodayView(text: $appState.todayText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            if appState.isOpenLoopsOverlayPresented {
                OpenLoopsOverlay(isPresented: $appState.isOpenLoopsOverlayPresented)
                    .zIndex(3)
            }
        }
        .animation(DesignMotion.slip, value: appState.isSlipPresented)
        .animation(DesignMotion.commandPaletteOpen, value: appState.isCommandPalettePresented)
        .animation(DesignMotion.panel, value: appState.isOpenLoopsOverlayPresented)
        .task { await appState.prepareWorkspace() }
        .onChange(of: appState.todayText) { _, _ in
            appState.handleTodayTextChange()
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

private struct OpenLoopsOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.06)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }

                OpenLoopsView()
                    .frame(width: 560)
                    .frame(maxHeight: proxy.size.height * 0.7)
                    .background(DesignTokens.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                            .stroke(DesignTokens.hairline.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))

                Button("") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
