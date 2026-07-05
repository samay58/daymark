# Milestone 7 Orchestration Ledger

Doctrine: `~/.claude/FABLE-ORCHESTRATION.md`. Success bar: Fable at or below 20 percent of session output tokens, all gates green, Samay rates the result excellent. Updated at each phase boundary.

## Measurement

Output tokens by model over the session transcript(s):

Transcript lines repeat cumulative usage per streaming chunk, so dedupe by message id and take the max per id. Sum the two session files plus every `subagents/**/agent-*.jsonl` for the sessions involved (subagent output does NOT land in the parent transcript). Do not glob all `*.jsonl` in the project dir; it contains pre-M7 sessions.

```bash
jq -rs '[ .[] | select(.type == "assistant" and .message.usage.output_tokens != null)
  | {id: .message.id, m: .message.model, o: .message.usage.output_tokens} ]
  | group_by(.id) | map({m: .[0].m, o: (map(.o) | max)})
  | group_by(.m) | map("\(.[0].m)\t\(map(.o) | add)") | .[]' <transcript files>
```

## Output tokens by tier

| Phase boundary | Fable | Opus 4.8 | Sonnet 5 | Haiku 4.5 | Fable share |
|---|---|---|---|---|---|
| After Phase 1 | 105,057 | 58,174 | 45,540 | 10,086 | 48 percent |
| After Phase 2 | 141,769 | 192,322 | 115,416 | 10,086 | 31 percent |
| After Phase 3 | 190,962 | 300,428 | 307,930 | 10,086 | 24 percent |
| After walk fixes | 210,628 | 388,573 | 321,903 | 10,086 | 23 percent |

Phase 1 note: the Fable share is front-loaded by design; the spec (333 lines), the packet plan, ADR-012, and both gates are Fable deliverables. No implementation code was written by Fable. The share must fall through Phases 2 to 4 as Opus/Sonnet packets dominate output.

## Gate log

| Gate | Result | Notes |
|---|---|---|
| Phase 0 | done | Spec, plan, ADR-012, roadmap renumber committed; paperwork only, no code |
| Phase 1 | green | 236 library tests, 41 CLI tests, both products build, app launch smoke against temp workspace. Spike verdict: fragment (Mechanism A passes all acceptance items; keystroke latency 0.06 to 0.29ms median on a 5k-line note with a collapsed card). Toolchain workaround recorded in CLAUDE.md (DEVELOPER_DIR plus --build-system native) |
| Phase 2 | green after one fix round | Adversarial review returned five findings (one high: perf-rewritten scanLines lost fence-awareness, confirmed with a standalone repro; the builder's own matrix had it as PASS). Fix packet (Sonnet, design pinned by Fable) plus independent re-verify (Opus): all five dead, no new findings. Gate re-ran the battery first-hand: 247 library tests, 41 CLI tests, both products, plus source spot-checks of each fix. Keystroke path 0.008ms release on 5k lines. Interactive click walk deferred to the Phase 4 acceptance pass (no GUI-automation permission in builder sandbox) |
| Phase 3 | green after one fix round | Five-stage pipeline (chrome, cards, cardui, codex, adversarial review) interrupted once by an Opus session limit and resumed from cache. Review verdict pass with two low findings; cardui honestly flagged an unreachable spec state (two-way reveal strip). One Sonnet fix packet closed all three. Gate ran the battery (247 plus 41, both products), fix spot-checks in source, and the full temp-workspace dynamic-blocks end-to-end check (dry-run clean, apply idempotent, user text preserved, injected generated checkbox does not feed back, cache-delete recovery, doctor clean). Visual and interactive confirmation deferred to Samay's walk, a formal gate step. Desktop-courtesy rule added mid-phase after builders and orchestrator both encountered the user's live desktop |
| Walk fixes | green | Samay's first real-display walk produced a spec addendum (rollover copy, machine-text concealment, four bugs, card v2, glass token, calmer codex). Opus bug packet root-caused each of the four (toggle scheduled a needless whole-note restyle; scroll-chrome adapter attached before the view had a window and was masked by the tint; reveal transitions invalidated layout but not display, leaving ghost glyphs; no cursor branch for checkboxes) plus machine-text concealment (9 new tests). Sonnet copy packet killed "rolled over" everywhere. Gate: 256 library, 41 CLI, both products, source spot-checks. Note: session model switched to Opus 4.8 mid-milestone, so orchestrator output is recorded as Opus from here, which loosens the Fable-tier reading of remaining rows |

## Final report

Pending milestone completion: total spend by tier, Fable share, counterfactual all-Fable estimate, Samay's quality rating.
