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

Phase 1 note: the Fable share is front-loaded by design; the spec (333 lines), the packet plan, ADR-012, and both gates are Fable deliverables. No implementation code was written by Fable. The share must fall through Phases 2 to 4 as Opus/Sonnet packets dominate output.

## Gate log

| Gate | Result | Notes |
|---|---|---|
| Phase 0 | done | Spec, plan, ADR-012, roadmap renumber committed; paperwork only, no code |
| Phase 1 | green | 236 library tests, 41 CLI tests, both products build, app launch smoke against temp workspace. Spike verdict: fragment (Mechanism A passes all acceptance items; keystroke latency 0.06 to 0.29ms median on a 5k-line note with a collapsed card). Toolchain workaround recorded in CLAUDE.md (DEVELOPER_DIR plus --build-system native) |

## Final report

Pending milestone completion: total spend by tier, Fable share, counterfactual all-Fable estimate, Samay's quality rating.
