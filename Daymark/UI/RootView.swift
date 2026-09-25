import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .top) {
            CodexPopoverHost(appState: appState)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            TodayView(text: $appState.todayText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.canvas)

            if appState.isSlipPresented {
                SlipPanelView(isPresented: $appState.isSlipPresented)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }

            if appState.isCommandPalettePresented {
                ZStack(alignment: .top) {
                    OverlayScrim { appState.isCommandPalettePresented = false }
                    CommandPaletteView(isPresented: $appState.isCommandPalettePresented)
                        .padding(.top, 96)
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
                .zIndex(2)
            }

            if appState.isOpenLoopsOverlayPresented {
                OpenLoopsOverlay(isPresented: $appState.isOpenLoopsOverlayPresented)
                    .zIndex(3)
            }

            ReceiptCard(appState: appState)
                .zIndex(4)
        }
        .animation(reduceMotion ? nil : DesignMotion.slip, value: appState.isSlipPresented)
        .animation(reduceMotion ? nil : DesignMotion.commandPalette, value: appState.isCommandPalettePresented)
        .animation(reduceMotion ? nil : DesignMotion.panel, value: appState.isOpenLoopsOverlayPresented)
        .animation(reduceMotion ? nil : DesignMotion.stateChange, value: appState.codexReceipt != nil)
        .task { await appState.prepareWorkspace() }
        .onChange(of: appState.todayText) { _, _ in
            appState.handleTodayTextChange()
        }
    }
}

// The faint wash behind a modal overlay. A click anywhere on it dismisses the overlay.
private struct OverlayScrim: View {
    let dismiss: () -> Void

    var body: some View {
        Color(white: 0, opacity: 0.06)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .accessibilityElement()
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dismiss() }
    }
}

private struct OpenLoopsOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayScrim { isPresented = false }

                OpenLoopsView()
                    .frame(width: 560)
                    .frame(maxHeight: proxy.size.height * 0.7)
                    .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
