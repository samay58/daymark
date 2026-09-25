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
                    .font(DesignType.pillSymbol)
            }
            Text(text)
        }
        .font(DesignType.pill)
        .foregroundStyle(textColor)
        .padding(.horizontal, DesignMetrics.pillPadding)
        .padding(.vertical, 2)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.pillRadius, style: .continuous))
    }
}

// Filled sage primary action, e.g. "Create" or "Apply".
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignType.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : DesignTokens.disabledOpacity)
    }
}

// Hairline outline secondary action, e.g. "Reveal in Finder".
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignType.button)
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
            .opacity(isEnabled ? 1 : DesignTokens.disabledOpacity)
    }
}

// Quiet text action, e.g. "Cancel" or "Done".
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignType.button)
            .foregroundStyle(configuration.isPressed ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : DesignTokens.disabledOpacity)
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignType.fieldLabel)
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

// The one box style for text fields and read-only values: field fill, card radius, hairline.
struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DesignTokens.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            }
    }
}

// A labelled, non-editable value box, used by the Codex composer and the context bundle preview.
struct ReadOnlyField: View {
    let label: String
    let value: String
    var lines: Int = 1
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            Text(value)
                .font(mono ? DesignType.fieldMono : DesignType.field)
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * DesignType.fieldLineHeight, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .fieldChrome()
        }
    }
}

// Chrome for every floating surface (capture slip, command palette, Open Loops, receipt card):
// the day header's material and tint, plus a hairline border and panelRadius, so all chrome
// reads as one material rather than separate blurs. The shadow sets how far it floats.
struct GlassSurface: ViewModifier {
    var shadow: DesignShadow

    func body(content: Content) -> some View {
        content
            .background(GlassBackground(opaqueFallback: DesignTokens.surface))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                    .stroke(DesignTokens.glassStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

// The within-window material with the warm canvas tint over it. Reduce Transparency swaps it
// for an opaque token fill, since a blur the user asked to remove must not show at all.
struct GlassBackground: View {
    let opaqueFallback: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueFallback
        } else {
            ZStack {
                GlassMaterialView()
                DesignTokens.canvas.opacity(DesignTokens.glassTintOpacity)
            }
        }
    }
}

// Within-window blending, so the material blurs note content under it rather than the desktop.
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
    func glassSurface(_ shadow: DesignShadow) -> some View { modifier(GlassSurface(shadow: shadow)) }
    func fieldChrome() -> some View { modifier(FieldChrome()) }
}
