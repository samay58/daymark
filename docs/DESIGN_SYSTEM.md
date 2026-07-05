# Design System

## Visual Direction

Daymark should feel like a quiet native notebook, not productivity SaaS.

The mockups in `reference/mockups/` are the original visual reference. Milestone 7 (Dynamic Note Surface, `docs/superpowers/specs/2026-07-05-dynamic-note-surface-design.md`, ADR-012) built the single-pane shell they always pointed at. The strongest cues are:

- Warm paper canvas.
- Single centered writing column. No sidebar, no right-margin panel.
- Native chrome materials, used sparingly (the header band, floating overlays), never under body text.
- Graphite text.
- Sparse sage accent.
- Soft document-like cards for generated content.
- Minimal toolbar chrome.
- No chatbot layout.

## Color Tokens

Light mode is the default visual direction.

```txt
canvas:         #FAF8F5
surface:        #F3F1EE
surfaceWarm:    #F5F2EC
textPrimary:    #1C1C1E
textSecondary:  #6E6E73
textTertiary:   #9A958C
hairline:       #E6E4E1
accent:         #7E937F
accentSoft:     #E9EFE9
accentDeep:     #4F634F
warning:        #A15C38
success:        #5E755A
checkboxBorder: #C9C5BE
pillDueFill:    surfaceWarm alias
cardIslandFill: surface alias
dateTileFill:   surfaceWarm alias
```

`accentDeep` is tag pill text (contrast 4.5:1 or better on `accentSoft`). `checkboxBorder` is the empty checkbox stroke. `pillDueFill`, `cardIslandFill`, and `dateTileFill` are aliases onto existing fills, not new hues, kept as separate tokens so a surface can retint on its own later without touching the others.

Dark mode tokens may exist for system support, but Daymark should not become dark-first unless explicitly approved.

## Typography

Use Apple system fonts. Do not import a fashionable web font.

```txt
Daily date:         SF Pro Display, 28-30, regular or semibold, line height 34-36
Section heading:    SF Pro Text, 17-20, semibold, line height 25-28
Body:               SF Pro Text, 15.5-16, regular, line height 24
Task:               SF Pro Text, 15.5-16, regular, line height 24
Metadata:           SF Pro Text, 12, regular or medium, line height 16
Command palette:    SF Pro Text, 14, regular, line height 20
Code/spec:          SF Mono, 13, regular, line height 18-20
Date tile numeral:  SF Pro Text, 26, semibold
Card header:        SF Pro Text, 12, semibold, tracking +0.5
Pill:               SF Pro Text, 13, regular
```

## Layout

Default window:

```txt
Width:          860 px
Height:         720 px
Minimum width:  620 px
Minimum height: 520 px
```

The window never opens maximized or zoomed. If a restored frame covers 90 percent or more of the screen's visible frame in either dimension, launch resets it to the default size, centered on the active screen. A user resize during a session is respected on the next launch unless it crosses that threshold again, and the zoom button works normally after launch.

Regions:

```txt
Editor column:  centered, max width 720 px. No sidebar, no right-margin panel; both retired in Milestone 7.
Day header:     floats as a material band over the top of the editor column.
Overlays:       command palette, capture slip, Open Loops, Codex popover, receipt card. Layered above the canvas; none reserve layout space.
```

Daily note top padding: 48 px, reserved by the day header.

Editor body max width: 720 px.

## Day header

The app's only persistent chrome above the note, not note content:

- Date tile: 48x48, `dateTileFill`, hairline border, radius 10 (`dateTileRadius`). Day-of-month numeral in the `dateTileNumeral` type style, centered.
- Month and weekday stack to the tile's right: month 16pt semibold `textPrimary`, weekday 13pt `textSecondary`.
- Brief strip, one line below the tile row, 13pt `textSecondary`, middot-separated segments: "N from yesterday" when tasks rolled forward, "N open loops", and the save state ("Saved" or "Saving"). Empty segments are omitted. Clicking the strip opens the Open Loops overlay.
- Three quiet icon buttons at the header's right edge: capture slip, command palette, Open Loops.

## Materials and translucency

Depth lives in the chrome, never under body text. The writing canvas stays opaque warm paper.

The day header is a native material band (`NSVisualEffectView`, within-window blending) with a warm canvas tint layered over it. `DesignTokens.glassTintOpacity` (currently 0.6) is the single tunable knob for how much of that tint shows through: note content passing under the header visibly blurs as it scrolls, and a hairline fades in along the header's bottom edge once the note has scrolled. Floating overlays (command palette, capture slip, Open Loops, receipt card, Codex popover) sit on `.regularMaterial` with hairline borders rather than flat opaque fills.

When the system Reduce Transparency setting is on, every material degrades to its opaque token fill: the header falls back to a flat `canvas` fill.

## Radius and Cards

Use 8 px for cards by default. Use 10 to 12 px only for larger panels, windows, or the date tile where the mockups need a softer native surface.

Do not exceed 12 px without a decision record.

Cards should feel like paper on paper:

- 14 to 16 px padding.
- Soft shadow only when needed.
- Prefer hairline and background contrast to heavy shadow.
- No chatbot bubbles.
- No left border ribbons.

## Dynamic block cards

A well-formed `<!-- daymark:block-begin -->` / `<!-- daymark:block-end -->` generated region renders as an embedded card in place of its literal text, at full column width.

Chrome: `cardIslandFill`, hairline border, `panelRadius` (12), 14pt padding. Header row: the block title in the `cardHeader` type style, derived from the command (`OPEN LOOPS`, `SOURCES`, `CODEX CONTEXT`, `WEEKLY REVIEW`, or `GENERATED` when no command line is adjacent), a refresh icon button, and a view-source toggle.

States:

- Idle: header and body, no footer.
- Preview pending: after a refresh, a one-line change summary plus Apply and Cancel.
- Stale: the buffer changed after preview; the summary reads "Note changed; preview again" and Apply disables.
- Source revealed: the card collapses to a thin header strip pinned above the literal region text; the toggle re-collapses it. Caret entry into the region also reveals it.

Malformed regions (unpaired markers, hash mismatch) never render as a card; the literal text shows with plain styling. Content is hidden only when a region parses as a complete, well-formed pair.

## App Icon

Direction:

- Warm rounded square.
- Small daymark/navigation marker symbol.
- Graphite or deep sage mark.
- Subtle depth.
- No sparkles.
- No robot.
- No phoenix.
