# Self-Test: Milestone 4 Codex Handoff

Use this to test the first Codex Handoff slice without touching your real `~/phoenix`.

## CLI test with a safe workspace

1. Open a terminal in the Daymark repo:

   ```bash
   cd /Users/samaydhawan/Projects/active/daymark
   ```

2. Build the CLI:

   ```bash
   swift build --product daymark
   ```

3. Create a temporary workspace and sample note:

   ```bash
   ROOT="$(mktemp -d)"
   mkdir -p "$ROOT/daily/2026/06"
   cat > "$ROOT/daily/2026/06/2026-06-29.md" <<'MD'
   # Today

   ## Capture

   Build selected text to Codex task handoff.
   Keep source note unchanged.
   MD
   ```

4. Preview the task file. This should not write anything:

   ```bash
   .build/arm64-apple-macosx/debug/daymark codex-task --root "$ROOT" --source daily/2026/06/2026-06-29.md --line 5 --date 2026-06-29
   ```

5. Read the preview. It should show a target path under `specs/tasks/`, a title, a goal, the source note path and line, the source excerpt, constraints, and acceptance criteria.

6. Approve the write:

   ```bash
   .build/arm64-apple-macosx/debug/daymark codex-task --root "$ROOT" --source daily/2026/06/2026-06-29.md --line 5 --date 2026-06-29 --apply
   ```

7. Open the generated task file:

   ```bash
   cat "$ROOT/specs/tasks/2026-06-29-build-selected-text-to-codex-task-handoff.md"
   ```

8. Confirm the original note did not change:

   ```bash
   cat "$ROOT/daily/2026/06/2026-06-29.md"
   ```

9. Run the same apply command again. It should create a second file with `-2.md` instead of overwriting the first file:

   ```bash
   .build/arm64-apple-macosx/debug/daymark codex-task --root "$ROOT" --source daily/2026/06/2026-06-29.md --line 5 --date 2026-06-29 --apply
   ls "$ROOT/specs/tasks"
   ```

10. Clean up when done:

    ```bash
    rm -rf "$ROOT"
    ```

## App test

1. Build and run the app:

   ```bash
   swift run Daymark
   ```

2. Use a safe workspace in Settings if you do not want to test against `~/phoenix`.

3. Put the cursor inside a note block with real text, or select text in Today. Empty section headings should not create task files.

4. Press Command Shift C.

5. The right-side Codex Task Composer should show the draft and the exact Markdown that will be written.

6. Click `Create Task File`.

7. Check the generated file under `specs/tasks/`.

8. Confirm the source note still has the same text.
