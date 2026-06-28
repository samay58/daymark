# Extension Interaction Contract

This is the QA contract for Cold Start extension motion and interaction polish.
It exists so interaction quality is observable, repeatable, and still faithful to
the Catalogue Card direction in `DESIGN.md`.

## Global Rules

- Pointer-driven objects must stay visually attached to the pointer. Target:
  sampled dragged-card center stays within 3px of expected pointer position.
- Drag must not trigger click activation unless the user performs a plain tap or
  click.
- Keyboard activation must work for every pointer activation.
- Focus rings must be visible, tasteful, and not clipped.
- Reduced motion must preserve state meaning without spatial motion.
- Prefer transform and opacity for repeated or gesture-driven motion.
- Avoid `transition: all`.
- Avoid layout animation on pointer-driven elements.
- Helper copy can fade or settle quickly, but should not use springy opacity.

## Craft Rules

- Keep the pile metaphor active. Dormant modules are filed research cards, not
  generic settings rows.
- Preserve Cold Start cues: catalogue-card edges, call-number rhythm, dusty-lilac
  seal accent, warm paper, and precise filing language.
- Re-engineer expressive details before removing them. Smooth should not mean
  flat.
- Tests should protect behavior and feel, not freeze decorative implementation.

## Surface Matrix

| Surface | States | Required proof |
| --- | --- | --- |
| Dormant card pile | Rest, hover, focus, press, drag cancel, preview, snap-ready, release | Playwright assertions plus screenshots |
| Active research module | Expanded, collapsed handoff, queued, running, populated | Playwright assertions plus screenshot |
| Progress panel | Idle, running, reduced motion | Playwright assertions plus screenshot |
| Tooltip controls | Hover, focus, dismiss | Playwright assertions |
| Utility controls | Links, copy, regenerate, generation gate | Playwright assertions |
| Accessibility | Keyboard traversal, focus visibility, reduced motion | Playwright assertions |

## Motion Ownership Audit

| Element | Motion owner | Safe? | Notes |
| --- | --- | --- | --- |
| Dormant card frame | Framer `animate` owns stack x/y/rotation/scale | Yes | Outer frame creates pile depth. |
| Dormant card inner | Framer drag owns gesture `y` | Yes | Inner card settles its own motion value after release. |
| Dormant card tray | CSS z-index and pseudo-card state only | Yes | Tray does not move during live drag. |
| Filing slot | Framer enter/exit opacity/scale/y | Yes | Absolute overlay, so it does not reflow the source pile. |
| Active module body | CSS `grid-template-rows` | Acceptable | Short, local, non-pointer-driven expansion. |
| Running sheen | CSS keyframes | Acceptable | Decorative progress cue disabled under reduced motion. |
| Source pass/progress | CSS keyframes and small transforms | Acceptable | Scoped to progress affordances and covered by reduced-motion tests. |
| Start screen entrance | Framer one-shot opacity/y/filter | Acceptable | Not gesture-driven; keep short and non-blocking. |
| Start screen pointer glow | Framer springed motion values | Acceptable | Decorative only; disabled by reduced-motion spring settings. |
| Shared tooltip | CSS top/left transition | Acceptable | Small surface, only used to keep tooltip continuity between triggers. |

## Known Exceptions

- `.cs-active-enrichment-body-frame` uses `grid-template-rows` for local expand
  and collapse. This is allowed because it is not pointer-driven and keeps module
  contents accessible in normal document flow.
- Small static `filter` and `backdrop-filter` treatments exist on isolated
  surfaces. Do not animate them continuously.
- Box-shadow may change on small interactive cards and buttons as feedback. Do
  not animate large-container shadows during gestures.

## Acceptance Checklist

- Dormant card drag remains attached within 3px in sampled states.
- Short drag settles back and never files a card.
- Snap drag files a card cleanly.
- Keyboard activation works for every dormant module.
- Reduced motion disables sweeping decorative motion while keeping state readable.
- Focus is visible on all reachable controls.
- No temporary probes, debug logs, or console noise remain.
- `npm run qa:extension:ui -w @cold-start/extension` passes.
- `npm run qa:extension:smoke -w @cold-start/extension` passes.
- `npm run check` passes before production rollout.
