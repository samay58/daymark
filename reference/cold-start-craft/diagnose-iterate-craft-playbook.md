# Diagnose And Iterate Craft Playbook

This note captures the working method that has been producing better Cold Start design work. It is not a replacement for `DESIGN.md`. Treat `DESIGN.md` as the visual source of truth and use this as the interaction-craft operating model.

The loop is simple:

- Diagnose the real state model before touching pixels.
- Name which UI is telling the truth and which UI is ornamental.
- Preserve useful immediacy. Do not make the user wait for a prettier transition.
- Collapse progress once it has done its job.
- Test the mechanics, not just the happy-path render.

## What We Learned

### Progress Should Move Across Views, Not Restart

The first progress cleanup exposed a subtle product problem. The full progress page showed four steps, but the sidebar moved to the profile as soon as the starter profile existed. That made the later progress steps mostly decorative.

The good fix was not to keep the user on the progress page longer. The profile should appear as soon as it is useful. The fix was to carry the same run story into the profile view in a smaller form.

Reusable rule:

- Full progress is for the pre-profile state.
- Compact progress is for the profile-visible, still-running state.
- Completed progress becomes a receipt, not a second feature area.

Good complete-state copy:

```text
Research filed · 35 sources · 9 of 9 sections
```

Bad complete-state behavior:

- Showing a full four-step chain after the run is done.
- Repeating old substeps because events still exist.
- Letting progress compete with the actual research modules.

### Drag Needs A Real Destination

The module-card drag diagnosis found that the behavior worked, but the gesture felt wrong. The card could be dragged and activated, but the destination was a small dashed strip above the tray. It looked like a placeholder, not a place the card belonged.

The better model is direct manipulation:

- The object follows the hand.
- The destination responds before release.
- The insertion slot is inside the real Research module stack.
- Release settles the same object into the place it is going.
- The module keeps visual continuity without morphing text between mismatched layouts.

Reusable rule:

- If drag is kept, the destination must be real.
- If drag cannot be excellent in the side panel, make click or keyboard activation the primary path and demote drag.

### Shared Layout Is Not Free Craft

Shared element transitions are only tasteful when the source and destination have compatible structure. If a dormant card and an active card share a `layoutId` while using different grids, icon sizes, and title sizes, Framer will interpolate the mismatch. That is how you get the title balloon.

Reusable rule:

- Use shared layout for the shell, position, and spatial continuity.
- Do not ask text to morph between different typography systems.
- If the destination needs larger type, mount it at the final size after the shell settles.

### Accordions Need A Hard Invariant

The active card stack should not feel negotiable or glitchy. One card open at a time is the clearest model. Letting the current card close to `null` creates an unstable gap, especially when storage or polling effects can reopen something.

Reusable rule:

- When active modules exist, exactly one module is open.
- Clicking a closed card opens it and closes the previous one.
- Clicking the already-open card keeps it open unless there is a deliberate separate collapse control.
- Keyboard behavior follows the same invariant.

## The Craft Checklist

Use this before implementing sidebar design changes.

- State: What exact state or event causes the UI to change?
- Truth: Is the visible progress backed by real events, or is it decorative?
- Hierarchy: What should regain priority once the profile is usable?
- Continuity: Does the same user action feel like one story across views?
- Destination: If something moves, where is it really going?
- Typography: Are we morphing text between incompatible sizes or grids?
- Motion: Is the motion explaining state, or showing off?
- Completion: What collapses once the work is done?
- Failure: What stays visible because the user needs reassurance?
- Accessibility: Is the same action available through click, keyboard, and reduced motion?
- QA: Are we testing the invariant, or only testing that something appears?

## Cold Start-Specific Defaults

- Keep the profile visible as soon as it is useful.
- Keep global progress quiet once modules are available.
- Put section-level running state inside the active module.
- Use existing research events instead of inventing another progress system.
- Deduplicate repeated event copy before rendering it.
- Avoid dashed drop zones, toy bounce, glow, oversized radii, and generic SaaS progress chrome.
- Preserve the Catalogue Card direction: warm, quiet, precise, evidence-led.

## Files To Inspect First

- `DESIGN.md`
- `apps/extension/src/ResearchLayerPanel.tsx`
- `apps/extension/src/SourcePassInstrument.tsx`
- `apps/extension/src/research-progress.ts`
- `apps/extension/src/research-layer-motion.ts`
- `apps/extension/src/motion-primitives.ts`
- `apps/extension/src/styles.css`
- `apps/extension/src/research-layer.ts`
- `apps/extension/tests/e2e/sidepanel-ui.spec.ts`
- `apps/extension/tests/sidepanel.test.tsx`

## Test The Feeling

A passing functional test is not enough for these interactions. The current drag test proves that the card activates. It does not prove that the card glides naturally, that the destination feels real, that typography stays stable, or that accordion state is robust.

Add tests for:

- Current-stage progress while running.
- Receipt-only progress after completion.
- Duplicate event copy removal.
- One-open-card invariant.
- No reopen loop after polling or storage refresh.
- Drag preview, snap-ready, release, cancel, and click suppression.
- Reduced-motion behavior.
- Narrow sidebar height and scroll position.

Captured from the Cold Start progress and module-card diagnoses on 2026-06-05.
