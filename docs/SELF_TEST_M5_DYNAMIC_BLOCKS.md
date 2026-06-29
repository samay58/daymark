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
