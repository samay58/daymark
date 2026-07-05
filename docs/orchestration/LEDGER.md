# Milestone 7 Orchestration Ledger

Doctrine: `~/.claude/FABLE-ORCHESTRATION.md`. Success bar: Fable at or below 20 percent of session output tokens, all gates green, Samay rates the result excellent. Updated at each phase boundary.

## Measurement

Output tokens by model over the session transcript(s):

```bash
jq -rs '[ .[] | select(.type == "assistant" and .message.usage.output_tokens != null)
  | {m: .message.model, o: .message.usage.output_tokens} ]
  | group_by(.m) | map({model: .[0].m, out: (map(.o) | add)}) | .[]
  | "\(.model)\t\(.out)"' \
  ~/.claude/projects/-Users-samaydhawan-Projects-active-daymark/<session-id>.jsonl
```

Subagent calls land in the same transcript, so the split is complete. Add workflow `budget.spent()` figures per run when workflows report them.

## Output tokens by tier

| Phase boundary | Fable | Opus 4.8 | Sonnet 5 | Haiku 4.5 | Fable share |
|---|---|---|---|---|---|
| (pending Phase 1) | | | | | |

## Gate log

| Gate | Result | Notes |
|---|---|---|
| Phase 0 | done | Spec, plan, ADR-012, roadmap renumber committed; paperwork only, no code |

## Final report

Pending milestone completion: total spend by tier, Fable share, counterfactual all-Fable estimate, Samay's quality rating.
