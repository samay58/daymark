# Self-Test: Milestone 5 Dynamic Blocks

Use a temp workspace for every mutating check. Do not run apply against `~/phoenix` unless Samay explicitly asks.

## CLI `/daymark open-loops` Preview and Apply

1. Build the CLI product you are about to run:

   ```bash
   swift build --product daymark
   ```

2. Create a temp workspace with one prior daily note containing open and completed tasks, plus one note containing a visible command:

   ```bash
   ROOT="$(mktemp -d /tmp/daymark-m5.XXXXXX)"
   mkdir -p "$ROOT/daily/2026/06"
   cat > "$ROOT/daily/2026/06/2026-06-28.md" <<'EOF'
   # Yesterday

   - [ ] call Sarah #deal/acme due:today
   - [x] already sent the note #deal/acme
   - [ ] review beta draft #deal/beta
   EOF
   cat > "$ROOT/daily/2026/06/2026-06-29.md" <<'EOF'
   Intro stays.
   /daymark open-loops #deal/acme
   Outro stays.
   EOF
   ```

3. Run a dry-run preview and confirm the note is unchanged:

   ```bash
   BEFORE="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --date 2026-06-29
   AFTER="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   test "$BEFORE" = "$AFTER"
   ```

4. Apply the refresh and confirm one generated region appears below the visible command. Confirm rebuildable cache metadata is recorded under `.daymark`:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --date 2026-06-29 --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -n "/daymark open-loops" "$ROOT/daily/2026/06/2026-06-29.md"
   test -f "$ROOT/.daymark/dynamic-blocks.json"
   grep -n '"rendererName" : "open-loops"' "$ROOT/.daymark/dynamic-blocks.json"
   ```

5. Apply again and confirm the generated region is replaced, not duplicated:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --date 2026-06-29 --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -c "call Sarah #deal/acme due:today" "$ROOT/daily/2026/06/2026-06-29.md"
   ```

6. Delete `.daymark` and apply again. The note should stay readable and idempotent because the command plus marker region live in Markdown, and cache metadata should be recreated:

   ```bash
   rm -rf "$ROOT/.daymark"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --date 2026-06-29 --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   test -f "$ROOT/.daymark/dynamic-blocks.json"
   ```

Expected result: dry-run writes nothing, apply updates the target note and records rebuildable cache metadata, repeated apply does not duplicate generated output, completed tasks are excluded, tag filtering works for existing task tags, and text outside the generated region is preserved.

## CLI `/daymark source-list #tag` Preview and Apply

1. Reuse a rebuilt CLI product:

   ```bash
   swift build --product daymark
   ```

2. Create a temp workspace with a tagged source note, a generated-only false match, and a note containing the visible command:

   ```bash
   ROOT="$(mktemp -d /tmp/daymark-m5-source-list.XXXXXX)"
   mkdir -p "$ROOT/daily/2026/06" "$ROOT/projects"
   cat > "$ROOT/daily/2026/06/2026-06-29.md" <<'EOF'
   # Today

   Intro stays.
   /daymark source-list #project/daymark
   Outro stays.
   EOF
   cat > "$ROOT/projects/daymark.md" <<'EOF'
   # Daymark Project

   Build local dynamic blocks. #project/daymark
   EOF
   cat > "$ROOT/projects/generated.md" <<'EOF'
   # Generated Only

   <!-- daymark:block-begin abc -->
   Generated #project/daymark
   <!-- daymark:block-end abc -->
   EOF
   ```

3. Preview and confirm the note is unchanged:

   ```bash
   BEFORE="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md
   AFTER="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   test "$BEFORE" = "$AFTER"
   ```

4. Apply and confirm one generated region, the tagged source, and cache metadata:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -n "Daymark Project" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -n '"rendererName" : "source-list"' "$ROOT/.daymark/dynamic-blocks.json"
   ```

5. Apply again, then delete `.daymark` and apply once more. The note should stay idempotent and cache metadata should be recreated:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   rm -rf "$ROOT/.daymark"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   test -f "$ROOT/.daymark/dynamic-blocks.json"
   ```

Expected result: dry-run writes nothing, apply inserts one readable Source List region, generated-only matches are ignored, repeated apply is idempotent, and cache remains rebuildable metadata.

## CLI `/daymark codex-context #tag` Preview and Apply

1. Reuse a rebuilt CLI product:

   ```bash
   swift build --product daymark
   ```

2. Create a temp workspace with a tagged source note, one task spec, one context bundle, a generated-only false match, and a note containing the visible command:

   ```bash
   ROOT="$(mktemp -d /tmp/daymark-m5-codex-context.XXXXXX)"
   mkdir -p "$ROOT/daily/2026/06" "$ROOT/projects" "$ROOT/specs/tasks" "$ROOT/artifacts/context-bundles"
   cat > "$ROOT/daily/2026/06/2026-06-29.md" <<'EOF'
   # Today

   Intro stays.
   /daymark codex-context #project/daymark
   Outro stays.
   EOF
   cat > "$ROOT/projects/daymark.md" <<'EOF'
   # Daymark Project

   Build local Codex handoff views. #project/daymark
   EOF
   cat > "$ROOT/specs/tasks/2026-06-29-ship-beta.md" <<'EOF'
   # Ship beta handoff

   ## Source

   Path: `projects/daymark.md`
   EOF
   cat > "$ROOT/artifacts/context-bundles/2026-06-29-ship-beta-context.md" <<'EOF'
   # Context Bundle: Ship beta handoff

   ## Task

   Task: `specs/tasks/2026-06-29-ship-beta.md`
   EOF
   cat > "$ROOT/specs/tasks/2026-06-29-generated.md" <<'EOF'
   # Generated Only

   <!-- daymark:block-begin abc -->
   #project/daymark
   <!-- daymark:block-end abc -->
   EOF
   ```

3. Preview and confirm the note is unchanged:

   ```bash
   BEFORE="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md
   AFTER="$(shasum -a 256 "$ROOT/daily/2026/06/2026-06-29.md")"
   test "$BEFORE" = "$AFTER"
   ```

4. Apply and confirm one generated region, the existing task spec, the existing context bundle, and cache metadata:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -n "Ship beta handoff" "$ROOT/daily/2026/06/2026-06-29.md"
   grep -n '"rendererName" : "codex-context"' "$ROOT/.daymark/dynamic-blocks.json"
   ```

5. Apply again, then delete `.daymark` and apply once more. The note should stay idempotent and cache metadata should be recreated:

   ```bash
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   rm -rf "$ROOT/.daymark"
   .build/arm64-apple-macosx/debug/daymark blocks refresh --root "$ROOT" --source daily/2026/06/2026-06-29.md --apply
   grep -c "daymark:block-begin" "$ROOT/daily/2026/06/2026-06-29.md"
   test -f "$ROOT/.daymark/dynamic-blocks.json"
   ```

Expected result: dry-run writes nothing, apply inserts one readable Codex Context region, generated-only matches are ignored, existing task specs and context bundles are listed without copying large excerpts, repeated apply is idempotent, and cache remains rebuildable metadata.

## Safety and Idempotency Checks (2026-06-29 hardening)

Automated coverage for these lives in `Tests/DaymarkCoreTests/DynamicBlockSafetyTests.swift`,
`Tests/DaymarkCoreTests/WorkspacePathTests.swift`, the new `DaymarkIndexerTests`, and the
`DaymarkCLITests` blocks/open-loops tests. Re-verify by hand against a temp workspace when
touching the dynamic-block paths:

1. Workspace confinement: `blocks refresh --source ../outside.md --apply` and an absolute
   `--source /tmp/outside.md --apply` both exit non-zero with an "outside the workspace"
   message and leave the outside file byte-for-byte unchanged.
2. CRLF preservation: a note saved with CRLF line endings keeps CRLF on every line after
   `--apply` (no bare LF is introduced inside or outside the generated region).
3. Fence matching: a `/daymark open-loops` line inside a code fence (including mixed ```` ``` ````
   and `~~~` markers, or a longer outer fence) is not executed; only commands outside fences run.
4. Unterminated region: a stray `<!-- daymark:block-begin ... -->` with no matching end marker
   does not hide following real tasks from `open-loops` or the index (the begin line and the
   text after it are preserved). Refresh planning over the same malformed region fails clearly.
5. Duplicate cache records: a hand-corrupted `.daymark/dynamic-blocks.json` with two records
   sharing the same source and command hash does not crash `--apply`; the note is still written
   and the duplicates collapse to one record (last write wins).
6. Deleted-note pruning: index two daily notes, delete one file, run `daymark rebuild`, and
   confirm the deleted note's tasks and search rows are gone (`open-loops` no longer lists them).
7. Open Loops freshness: `daymark open-loops` reflects the Markdown files on disk without a
   prior `daymark rebuild`, and drops a task immediately after its source note is deleted.
