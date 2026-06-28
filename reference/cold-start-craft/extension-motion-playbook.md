# Extension Motion Playbook

Cold Start motion should feel like evidence being resolved into a card. Quiet, precise, and causal. The product is for investors moving fast through company context, so motion has one job: show that the system understood the action and is making progress without stealing attention.

## Principles

- Motion must explain state. Apple frames good motion as status, feedback, instruction, and orientation. That maps cleanly here: source fetching, evidence sorting, section synthesis, and completion should each have a visible state. Source: [Apple Human Interface Guidelines: Motion](https://developer.apple.com/design/Human-Interface-Guidelines/motion).
- Feedback should be brief. Apple also warns against gratuitous animation, especially on frequent interactions. The extension gets used repeatedly, so recurring motion should be smaller than the first-run visual idea.
- Progress should be honest. Material Design treats progress indicators as status communication for ongoing processes, with determinate progress when the system can measure it and indeterminate progress when it cannot. Cold Start should not pretend exact progress when it only has elapsed time. Source: [Material Design progress indicators](https://m2.material.io/components/progress-indicators/web).
- Motion should preserve orientation. Material motion is about spatial relationships, functionality, and intention. When a research module moves from the tray into the active stack, the card should visibly become that module, not blink into a new object. Source: [Material motion](https://m1.material.io/motion/material-motion.html).
- Performance is part of taste. Use transform and opacity for moving pieces. Avoid layout and paint-heavy animation in the side panel. Source: [web.dev: Animations and performance](https://web.dev/animations-and-performance/).
- Reduced motion is not optional. Use static or simplified states for users who request less motion. Source: [web.dev: CSS animations and prefers-reduced-motion](https://web.dev/learn/css/animations).
- State changes should feel direct. Motion for React supports layout animation and shared element transitions through `layout` and `layoutId`; use those for card-to-stack movement, but keep transitions coordinated so parent and child motion do not fight. Source: [Motion for React layout animation](https://motion.dev/docs/react-layout-animations).

## Current Read

The extension already has a lot of motion. The problem is coordination.

- Build-card progress has too many simultaneous loops: rail shimmer, sheen, scan, cursor pulse, character text, and stage movement.
- The main progress stages are elapsed-time based. That is acceptable as a fallback, but it should look estimated, not authoritative.
- Section generation uses a good local card state, but the lilac shimmer is generic. It says loading, not resolving this section.
- The card tray has strong shared-element instincts, but the drag feedback is close to toy-like: lift, scale, rotate, tray deformation, and drop-zone label all compete.

## Motion Model

Use three layers:

- Acknowledgment: under 120ms. Button press, card grab, generate click. Tiny transform or opacity only.
- Transition: 160-260ms. Card enters active stack, section opens, stage label changes. One motion per relationship.
- Progress: ongoing. One signature loop at a time, paired with real copy and real state.

Build-card progress should use this stage language:

- Queue: worker accepted the request.
- Gather: providers are finding sources.
- Read: pages and enrichment records are being normalized.
- File: facts and citations are being assembled.

Until the API exposes live milestones to the extension, these stages are estimated. The UI should make that feel like a calm work pass, not a precise meter.

## First Implementation Pass

- Replace character-by-character stage text with a clean fade/slide.
- Keep the source-pass scan as the one signature progress loop.
- Remove redundant shimmer loops from the build-card rail.
- Calm the shared springs so stack motion feels filed, not bouncy.
- Keep reduced-motion behavior intact.

## Next Implementation Pass

- Extend `/api/generate` status to return compact recent `research_run_events` for the active run.
- Feed those events into `GenerationPanel`.
- Move progress stage selection from elapsed time to real event types:
  - `generation.started` -> Queue
  - `plan.ready` -> Gather
  - `source.found` -> Read
  - `card.partial` or extraction completion -> File
- For section generation, use section-specific event copy and source counts when available.
- Add one visual completion moment: a quick stamp/fill settle when the card or section becomes available.

## Sources

- https://developer.apple.com/design/Human-Interface-Guidelines/motion
- https://m2.material.io/components/progress-indicators/web
- https://m1.material.io/motion/material-motion.html
- https://web.dev/animations-and-performance/
- https://web.dev/learn/css/animations
- https://motion.dev/docs/react-layout-animations
- https://motion.dev/docs/react-animate-presence

---
*Captured: 2026-06-01*
