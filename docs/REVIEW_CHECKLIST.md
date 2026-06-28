# Review Checklist

## Product

- Does this move the current milestone forward?
- Does this respect the north star?
- Did it avoid non-goals?
- Did it avoid unnecessary surfaces?

## UX

- Does the change make the app calmer, faster, or clearer?
- Does the editor remain central?
- Are high-frequency interactions instant?
- Are animations restrained?
- Is the UI still native-feeling?

## Architecture

- Does Markdown remain source of truth?
- Does SQLite remain an index or projection?
- Are file writes atomic?
- Can the index be rebuilt?
- Are new dependencies justified?

## Performance

- Does typing avoid background work?
- Are performance budgets still plausible?
- Is indexing incremental?
- Are expensive operations off the main thread?

## Reliability

- Are tests added or updated?
- Are migrations safe?
- Are external edits considered?
- Does rollback or undo exist where needed?

## Codex Handoff

- Are generated specs human-readable?
- Do generated specs have source backlinks?
- Are acceptance criteria explicit?
- Can Codex use the output without hidden app state?

## Taste

- Does it avoid AI slop?
- Does it avoid dashboard creep?
- Does it avoid noisy badges?
- Does it feel like Daymark?
