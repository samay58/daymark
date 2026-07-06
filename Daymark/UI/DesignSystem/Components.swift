import SwiftUI
import AppKit

struct DateTile: View {
    let day: Int

    var body: some View {
        Text("\(day)")
            .font(DesignType.dateTileNumeral)
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: DesignMetrics.dateTileSize, height: DesignMetrics.dateTileSize)
            .background(DesignTokens.dateTileFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.dateTileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.dateTileRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
    }
}

struct TokenPill: View {
    let text: String
    let fill: Color
    let textColor: Color
    var leadingSymbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = leadingSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .regular))
            }
            Text(text)
        }
        .font(DesignType.pill)
        .foregroundStyle(textColor)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.pillRadius, style: .continuous))
    }
}

struct TagChip: View {
    let label: String
    var tinted: Bool = false

    var body: some View {
        TokenPill(
            text: label,
            fill: tinted ? DesignTokens.accentSoft : DesignTokens.surface,
            textColor: tinted ? DesignTokens.success : DesignTokens.textSecondary
        )
    }
}

// Filled sage primary action, e.g. "Create Task File".
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Hairline outline secondary action, e.g. "Edit" / "Preview draft".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.5 : 0.001))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// Quiet text action, e.g. "Dismiss" / "Cancel".
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

// Small uppercase letterspaced field label used inside cards.
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

// A labelled, non-editable value box used in the Codex Task Composer and Context Bundle panels.
struct ReadOnlyField: View {
    let label: String
    let value: String
    var lines: Int = 1
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 17, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                }
        }
    }
}

// Shared chrome for every floating surface (capture slip, command palette, Open Loops
// overlay, and later the Codex popover): the same within-window system material and warm
// tint the day header band uses, plus a hairline border and panelRadius, so all chrome reads
// as one material system rather than separate blurs. Falls back to the opaque `surface` fill
// when Reduce Transparency is on.
struct GlassSurface: ViewModifier {
    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                    .stroke(DesignTokens.hairline.opacity(0.6), lineWidth: 1)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            ) { _ in
                reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
    }

    @ViewBuilder
    private var fill: some View {
        if reduceTransparency {
            DesignTokens.surface
        } else {
            ZStack {
                GlassMaterialView()
                DesignTokens.canvas.opacity(DesignTokens.glassTintOpacity)
            }
        }
    }
}

// Same NSVisualEffectView recipe as the day header band (within-window blending, .headerView
// material) so every floating panel blurs identically to the header.
private struct GlassMaterialView: NSViewRepresentable {
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

extension View {
    func glassSurface() -> some View { modifier(GlassSurface()) }
}
