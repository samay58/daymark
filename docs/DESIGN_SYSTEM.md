# Design System

## Visual Direction

Daymark should feel like a quiet native notebook, not productivity SaaS.

The mockups in `reference/mockups/` are the current visual reference. The strongest cues are:

- Warm paper canvas.
- Native translucent sidebar.
- Centered writing column.
- Graphite text.
- Sparse sage accent.
- Soft document-like cards.
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
warning:        #A15C38
success:        #5E755A
```

Dark mode tokens may exist for system support, but Daymark should not become dark-first unless explicitly approved.

## Typography

Use Apple system fonts. Do not import a fashionable web font.

```txt
Daily date:       SF Pro Display, 28-30, regular or semibold, line height 34-36
Section heading:  SF Pro Text, 17-20, semibold, line height 25-28
Body:             SF Pro Text, 15.5-16, regular, line height 24
Task:             SF Pro Text, 15.5-16, regular, line height 24
Metadata:         SF Pro Text, 12, regular or medium, line height 16
Command palette:  SF Pro Text, 14, regular, line height 20
Code/spec:        SF Mono, 13, regular, line height 18-20
Sidebar:          SF Pro Text, 13, regular, line height 18
```

## Layout

Default window:

```txt
Width:          1120 px
Height:         760 px
Minimum width:  860 px
Minimum height: 560 px
```

Regions:

```txt
Sidebar:        228 px
Editor column:  700 to 760 px
Context margin: flexible, hidden by default
```

Daily note top padding: 48 px from top of editor region.

Editor body max width: 720 px.

## Radius and Cards

Use 8 px for cards by default. Use 10 to 12 px only for larger panels or windows where the mockups need a softer native surface.

Do not exceed 12 px without a decision record.

Cards should feel like paper on paper:

- 14 to 16 px padding.
- Soft shadow only when needed.
- Prefer hairline and background contrast to heavy shadow.
- No chatbot bubbles.
- No left border ribbons.

## Sidebar

The sidebar should feel like a quiet Mac app:

- Native material background.
- Small SF Symbols.
- Graphite labels.
- No bright icons.
- No red badges.
- No section overload.
- Counts only when actionable.

## App Icon

Direction:

- Warm rounded square.
- Small daymark/navigation marker symbol.
- Graphite or deep sage mark.
- Subtle depth.
- No sparkles.
- No robot.
- No phoenix.
