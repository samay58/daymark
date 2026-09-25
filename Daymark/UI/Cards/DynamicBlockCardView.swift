import SwiftUI
import DaymarkCore

/// The card shown in place of a collapsed generated region: idle, preview pending, stale, or
/// showing an error. While the region is revealed (caret inside, or the view-source toggle on)
/// it shrinks to `stripView`, a header-only strip above the literal region text the editor
/// draws; the toggle in the strip re-collapses it without moving the caret.
struct DynamicBlockCardView: View {
    let context: CardIslandContext
    let appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var refreshAngle = 0.0

    private var regionHash: String { context.region.hash }

    private var footer: Footer? {
        let preview = appState.dynamicBlockCardPreview(forRegionHash: regionHash)
        let error = appState.dynamicBlockCardErrors[regionHash]
        guard preview != nil || error != nil else { return nil }
        return Footer(preview: preview, error: error, isApplying: appState.isApplyingDynamicBlocks)
    }

    /// What the footer shows. One value so a single `onChange` catches every height change.
    private struct Footer: Equatable {
        var preview: DynamicBlockCardPreview?
        var error: String?
        var isApplying: Bool

        var message: String { error ?? preview?.summaryText ?? "" }
        var needsAttention: Bool { error != nil || preview?.isStale == true }
    }

    private enum DotState { case idle, pending, attention }

    var body: some View {
        let footer = footer
        Group {
            if context.isRevealed {
                stripView(footer: footer)
            } else {
                fullCardView(footer: footer)
            }
        }
        .onHover { hovering in
            guard isHovering != hovering else { return }
            withAnimation(reduceMotion ? nil : DesignMotion.fade) { isHovering = hovering }
        }
    }

    private func fullCardView(footer: Footer?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(footer: footer)
            CardMarkdownText(markdown: footer?.preview?.incomingMarkdown ?? context.innerText)
                .equatable()
                .id(footer?.preview == nil ? "current" : "incoming")
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 2)))
            if let footer {
                footerView(footer)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .animation(reduceMotion ? nil : DesignMotion.stateChange, value: footer)
        .onChange(of: footer) { _, _ in context.notifyHeightChanged() }
    }

    /// Thin strip shown while the region is revealed: the status dot and title, with the
    /// view-source toggle fading in on hover. The literal region text renders below it.
    private func stripView(footer: Footer?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            statusDot(footer: footer)
            titleText
            Spacer(minLength: 8)
            sourceToggleButton
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: DesignMetrics.cardStripHeight, alignment: .leading)
        .background(DesignTokens.canvas)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
    }

    private func header(footer: Footer?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            statusDot(footer: footer)
            titleText
            Spacer(minLength: 8)
            trailingControls(footer: footer)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
    }

    /// Tertiary at rest, accent while a change is offered, warning once the preview is stale or
    /// the last action failed. Decorative for VoiceOver: the footer states the same thing in words.
    private func statusDot(footer: Footer?) -> some View {
        let color: Color
        switch dotState(footer) {
        case .idle: color = DesignTokens.textTertiary
        case .pending: color = DesignTokens.accent
        case .attention: color = DesignTokens.warning
        }
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .animation(reduceMotion ? nil : DesignMotion.stateChange, value: color)
            .accessibilityHidden(true)
    }

    private func dotState(_ footer: Footer?) -> DotState {
        guard let footer else { return .idle }
        return footer.needsAttention ? .attention : .pending
    }

    private var titleText: some View {
        Text(CardIslandCommand.title(for: context.command))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignTokens.textSecondary)
    }

    /// Generated-at label, refresh, and view-source; all quiet until the card is hovered.
    private func trailingControls(footer: Footer?) -> some View {
        HStack(spacing: 10) {
            if footer == nil, let generatedAt = appState.dynamicBlockGeneratedAt(forRegionHash: regionHash) {
                Text("Generated \(Self.relativeFormatter.localizedString(for: generatedAt, relativeTo: Date()))")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            refreshButton
            sourceToggleButton
        }
    }

    /// One deliberate rotation acknowledges the tap before the preview eases in; instant under
    /// Reduce Motion.
    private var refreshButton: some View {
        Button {
            if !reduceMotion {
                withAnimation(DesignMotion.refreshSpin) { refreshAngle += 360 }
            }
            Task { await appState.previewDynamicBlocksRefresh(fromCard: regionHash) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textTertiary)
                .rotationEffect(.degrees(refreshAngle))
        }
        .buttonStyle(.plain)
        .help("Refresh dynamic blocks")
        .accessibilityLabel("Refresh dynamic blocks")
    }

    /// Shows the composite reveal state. Toggling it off clears only the user-driven half, so
    /// with the caret still inside the region the strip stays up and the toggle stays active.
    private var sourceToggleButton: some View {
        Button {
            context.setSourceRevealed(!context.isRevealed)
            context.notifyHeightChanged()
        } label: {
            Image(systemName: "curlybraces")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(context.isRevealed ? DesignTokens.accentDeep : DesignTokens.textTertiary)
        }
        .buttonStyle(.plain)
        .help(context.isRevealed ? "Hide source" : "View source")
        .accessibilityLabel(context.isRevealed ? "Hide source" : "View source")
    }

    private func footerView(_ footer: Footer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(footer.message)
                .font(DesignType.metadata)
                .foregroundStyle(footer.needsAttention ? DesignTokens.warning : DesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let preview = footer.preview {
                    Button("Apply") {
                        Task { await appState.applyDynamicBlockCard(regionHash: regionHash) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!preview.canApply)
                    Button("Cancel") {
                        appState.cancelDynamicBlockCard(regionHash: regionHash)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(footer.isApplying)
                } else {
                    Button("Dismiss") {
                        appState.dismissDynamicBlockCardError(regionHash: regionHash)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 2)))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
