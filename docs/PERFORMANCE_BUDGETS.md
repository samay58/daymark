# Performance Budgets

These are product requirements, not hopes.

```txt
Cold launch to editable Today:        < 1.2 s
Warm launch:                          < 250 ms
Slip open from global hotkey:         < 100 ms
Keystroke latency:                    < 16 ms
Autosave after debounce:              < 50 ms
Command palette local results:        < 50 ms
Search first result:                  < 120 ms
Search across 10k notes:              < 300 ms
Open daily note:                      < 100 ms
Task parser after save:               < 250 ms
Task rollover calculation:            < 250 ms
Codex task generation without AI:     < 500 ms
Codex task generation with model:     < 8 s, v1+
Dynamic block cached render:          < 100 ms
Dynamic block fresh local evaluation: < 500 ms
```

## Tactics

- Preload today, yesterday, and tomorrow.
- Keep SQLite connection warm.
- Use WAL mode.
- Use FTS5 for search.
- Index incrementally.
- Debounce parsing by 300 ms.
- Never parse the entire workspace on launch.
- Use atomic file writes.
- Keep editor buffer independent from DB projections.
- Cache command palette commands.
- Lazy-load dynamic block output.
- Defer embeddings until local search is excellent.
