import SwiftUI
import AppKit

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
    static let checkboxBorder = Color(hex: 0xC9C5BE)

    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 12

    /// Opacity of the warm canvas tint over the chrome's glass material (the day header and every
    /// `.glassSurface()`). Low enough that the material still reads as glass over warm paper.
    static let glassTintOpacity: Double = 0.6

    /// Text fields and read-only value boxes sit on glass or on the popover material, so a
    /// translucent white lifts them off either without a second hue.
    static let fieldFill = Color.white.opacity(0.6)

    /// The border of floating glass chrome, softer than a hairline on paper because the material
    /// behind it already separates the surface.
    static let glassStroke = hairline.opacity(0.6)

    /// A quiet control's background while hovered.
    static let hoverFill = Color.black.opacity(0.04)

    /// Applied by the shared button styles, so a disabled action dims the same way everywhere.
    static let disabledOpacity: Double = 0.55

    static let pillDueFill = surfaceWarm
    static let dateTileFill = surfaceWarm
}

enum DesignMetrics {
    static let windowWidth: CGFloat = 860
    static let windowHeight: CGFloat = 720
    static let minWindowWidth: CGFloat = 620
    static let minWindowHeight: CGFloat = 520

    static let editorMaxWidth: CGFloat = 720
    static let editorTopPadding: CGFloat = 48

    // One checkbox geometry for the editor's drawn box, Open Loops rows, and card symbols.
    static let checkboxSize: CGFloat = 16
    static let checkboxRadius: CGFloat = 4
    static let checkboxStroke: CGFloat = 1
    static let checkmarkStroke: CGFloat = 1.6

    static let pillRadius: CGFloat = 4
    static let pillPadding: CGFloat = 4
    static let dateTileSize: CGFloat = 48
    static let dateTileRadius: CGFloat = 10

    /// The dynamic-block card's header strip while its source is revealed. The layout fragment
    /// reserves exactly this slice above the region's first line, so the two must agree.
    static let cardStripHeight: CGFloat = 28

    static let toolbarIconSize: CGFloat = 26
    static let toolbarIconRadius: CGFloat = 6
}

/// Drop shadows for floating chrome, applied through `glassSurface(_:)`.
struct DesignShadow: Equatable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    /// Modal surfaces over a scrim: the command palette and Open Loops.
    static let overlay = DesignShadow(opacity: 0.14, radius: 24, y: 12)
    /// Panels that float beside the note without a scrim: the capture slip and the Codex receipt.
    static let floating = DesignShadow(opacity: 0.12, radius: 20, y: 8)
}

// Typography follows docs/DESIGN_SYSTEM.md. Apple system fonts only. Sizes the AppKit editor
// also needs are exposed as points so both renderers read one number.
enum DesignType {
    static let bodySize: CGFloat = 16
    static let fieldSize: CGFloat = 13
    static let pillSize: CGFloat = 13
    static let pillSymbolSize: CGFloat = 11

    static let body = Font.system(size: bodySize, weight: .regular)
    static let dayHeaderTitle = Font.system(size: 16, weight: .semibold)
    static let dayHeaderDetail = Font.system(size: 13, weight: .regular)
    static let metadata = Font.system(size: 12, weight: .regular)
    static let palette = Font.system(size: 14, weight: .regular)
    static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let dateTileNumeral = Font.system(size: 26, weight: .semibold)
    static let pill = Font.system(size: pillSize, weight: .regular)
    static let pillSymbol = Font.system(size: pillSymbolSize, weight: .regular)
    // Light weight brings the SF square's stroke close to the drawn box's 1pt line.
    static let checkboxSymbol = Font.system(size: DesignMetrics.checkboxSize, weight: .light)

    /// Popover and panel headings: Capture, Open Loops, the Codex composer, new blocks.
    static let panelTitle = Font.system(size: 15, weight: .semibold)
    /// The symbol that leads a panel heading.
    static let panelIcon = Font.system(size: 15, weight: .medium)
    /// Headings inside a smaller floating card, like the Codex receipt.
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    /// Small secondary labels: a dynamic block's title, a disclosure label.
    static let label = Font.system(size: 12, weight: .medium)
    /// Glyphs in quiet icon buttons: close, refresh, view source.
    static let controlIcon = Font.system(size: 12, weight: .medium)
    /// The glyph on a warning banner, a step heavier so it reads as a signal.
    static let warningIcon = Font.system(size: 12, weight: .semibold)
    /// Toolbar and palette row symbols.
    static let icon = Font.system(size: 14, weight: .regular)
    /// The command palette's query field.
    static let paletteQuery = Font.system(size: 15, weight: .regular)
    static let button = Font.system(size: 13, weight: .medium)
    /// Field captions and palette section headers.
    static let fieldLabel = Font.system(size: 11, weight: .medium)
    static let field = Font.system(size: fieldSize, weight: .regular)
    static let fieldMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// The one-line source chip in the Codex composer.
    static let chip = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let chipIcon = Font.system(size: 10, weight: .medium)

    /// Height of one line of field text, for sizing a multi-line value box by line count.
    static let fieldLineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: fieldSize)
        return ceil(font.ascender - font.descender + font.leading)
    }()

    // SwiftUI line spacing is additive, so this is the gap above each card row, not the leading.
    static let cardLineSpacing: CGFloat = 8

    /// Markdown heading sizes by level; level 4 and deeper share the last. The editor and cards
    /// both read this, so a heading keeps its size when it moves into a card.
    static func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 19
        case 3: return 17
        default: return 16
        }
    }

    static func heading(level: Int) -> Font {
        .system(size: headingSize(level: level), weight: .semibold)
    }
}

// Motion budgets from docs/INTERACTION_SPEC.md. Nothing in daily use exceeds 220 ms. Callers
// pass nil instead of these under Reduce Motion, so every change becomes a plain state swap.
enum DesignMotion {
    static let hover = Animation.easeOut(duration: 0.08)
    static let commandPalette = Animation.easeOut(duration: 0.09)
    static let slip = Animation.easeOut(duration: 0.09)
    /// Small crossfades: card hover controls, the brief strip notice, the receipt leaving.
    static let fade = Animation.easeOut(duration: 0.12)
    /// A surface changing state in place: card preview and status dot, the receipt arriving.
    static let stateChange = Animation.easeOut(duration: 0.16)
    /// The Open Loops overlay and the Codex Details disclosure.
    static let panel = Animation.easeOut(duration: 0.18)
    /// The card refresh icon's single turn, which acknowledges the tap.
    static let refreshSpin = Animation.easeOut(duration: 0.11)

    // The editor animates in AppKit through `EditorMotion`, so it takes durations, not curves.
    static let checkmarkDuration: CFTimeInterval = 0.14
    static let revealFadeDuration: CFTimeInterval = 0.11
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
