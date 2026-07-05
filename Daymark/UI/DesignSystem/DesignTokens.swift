import SwiftUI

enum DesignTokens {
    static let canvas = Color(hex: 0xFAF8F5)
    static let surface = Color(hex: 0xF3F1EE)
    static let surfaceWarm = Color(hex: 0xF5F2EC)
    static let textPrimary = Color(hex: 0x1C1C1E)
    static let textSecondary = Color(hex: 0x6E6E73)
    static let textTertiary = Color(hex: 0x9A958C)
    static let hairline = Color(hex: 0xE6E4E1)
    static let accent = Color(hex: 0x7E937F)
    static let accentSoft = Color(hex: 0xE9EFE9)
    static let accentDeep = Color(hex: 0x4F634F)
    static let warning = Color(hex: 0xA15C38)
    static let success = Color(hex: 0x5E755A)
    static let checkboxBorder = Color(hex: 0xC9C5BE)

    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 12

    /// Opacity of the warm canvas tint layered over the chrome's glass material (header band
    /// today; palette, slip, receipt, popover in P4). One taste-tunable knob for translucency.
    /// The spec's nominal 0.85 fully masked the blur over warm paper; lowered to 0.6 so the
    /// material reads as glass while keeping the warm identity (Bug 2). Reduce Transparency
    /// still degrades to an opaque canvas fill upstream.
    static let glassTintOpacity: Double = 0.6

    static let pillDueFill = surfaceWarm
    static let cardIslandFill = surface
    static let dateTileFill = surfaceWarm
}

enum DesignMetrics {
    static let windowWidth: CGFloat = 860
    static let windowHeight: CGFloat = 720
    static let minWindowWidth: CGFloat = 620
    static let minWindowHeight: CGFloat = 520

    static let editorMaxWidth: CGFloat = 720
    static let editorTopPadding: CGFloat = 48

    static let checkboxSize: CGFloat = 16
    static let checkboxRadius: CGFloat = 4
    static let pillRadius: CGFloat = 4
    static let dateTileSize: CGFloat = 48
    static let dateTileRadius: CGFloat = 10
}

// Typography follows docs/DESIGN_SYSTEM.md. Apple system fonts only.
enum DesignType {
    static let dailyDate = Font.system(size: 30, weight: .semibold)
    static let dailySubtitle = Font.system(size: 15, weight: .regular)
    static let sectionHeading = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let task = Font.system(size: 16, weight: .regular)
    static let metadata = Font.system(size: 12, weight: .regular)
    static let palette = Font.system(size: 14, weight: .regular)
    static let sidebar = Font.system(size: 13, weight: .regular)
    static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let dateTileNumeral = Font.system(size: 26, weight: .semibold)
    static let cardHeader = Font.system(size: 12, weight: .semibold)
    static let pill = Font.system(size: 13, weight: .regular)

    // SwiftUI line spacing is additive, so this is the gap above the glyph, not the full leading.
    static let bodyLineSpacing: CGFloat = 6
}

// Motion budgets from docs/INTERACTION_SPEC.md. Nothing in daily use exceeds 220 ms.
enum DesignMotion {
    static let hover = Animation.easeOut(duration: 0.08)
    static let commandPaletteOpen = Animation.easeOut(duration: 0.09)
    static let commandPaletteClose = Animation.easeOut(duration: 0.07)
    static let slip = Animation.easeOut(duration: 0.09)
    static let checkbox = Animation.spring(response: 0.18, dampingFraction: 0.72)
    static let popover = Animation.easeOut(duration: 0.14)
    static let panel = Animation.easeOut(duration: 0.18)
    static let dailyNavigation = Animation.easeOut(duration: 0.12)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
