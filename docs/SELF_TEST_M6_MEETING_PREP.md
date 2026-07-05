# Self Test: M6 Meeting Prep

This checks the first local-only meeting-prep slice. It uses a temp workspace and a user-provided JSON event snapshot. It must not touch real `~/phoenix`.

## Setup

```bash
swift build --product daymark

ROOT="$(mktemp -d)"
EVENT="$(mktemp /tmp/daymark-event.XXXXXX.json)"

mkdir -p "$ROOT/projects" "$ROOT/daily/2026/06" "$ROOT/specs/tasks" "$ROOT/artifacts/context-bundles"

cat > "$EVENT" <<'JSON'
{
  "title": "Acme Partner Sync",
  "startsAt": "2026-07-01T14:30:00Z",
  "endsAt": "2026-07-01T15:00:00Z",
  "attendees": ["Sarah Chen", "Maya Lee"],
  "location": "Zoom",
  "tags": ["#deal/acme"],
  "notes": "Discuss renewal questions."
}
JSON

cat > "$ROOT/projects/acme.md" <<'EOF'
# Acme Project

Renewal notes. #deal/acme
What changed in procurement?
EOF

cat > "$ROOT/daily/2026/06/2026-06-30.md" <<'EOF'
# Daily

- [ ] Send renewal model #deal/acme
- [x] Completed old note #deal/acme
EOF

cat > "$ROOT/specs/tasks/2026-06-30-acme-task.md" <<'EOF'
# Acme task

Path: `projects/acme.md`
EOF

cat > "$ROOT/artifacts/context-bundles/2026-06-30-acme-context.md" <<'EOF'
# Context Bundle: Acme task

Task: `specs/tasks/2026-06-30-acme-task.md`
EOF
```

## Dry Run

```bash
.build/arm64-apple-macosx/debug/daymark meeting-prep --root "$ROOT" --event-file "$EVENT"
test ! -d "$ROOT/meetings"
```

Expected:

- Output starts with `Target: meetings/2026-07-01-acme-partner-sync.md`.
- Output includes `# Meeting Prep: Acme Partner Sync`.
- Output cites `projects/acme.md`.
- Output includes the open task from the daily note.
- Output does not include the completed task.
- No `meetings/` directory is created.

## Apply

```bash
.build/arm64-apple-macosx/debug/daymark meeting-prep --root "$ROOT" --event-file "$EVENT" --apply
test -f "$ROOT/meetings/2026-07-01-acme-partner-sync.md"
```

Expected:

- Exactly one Markdown prep file appears under `meetings/`.
- Source notes, task specs, and context bundles are unchanged.
- The prep file cites local paths rather than copying long excerpts.

## Collision Safety

```bash
.build/arm64-apple-macosx/debug/daymark meeting-prep --root "$ROOT" --event-file "$EVENT" --apply
test -f "$ROOT/meetings/2026-07-01-acme-partner-sync-2.md"
```

Expected: repeat apply creates a suffix file and does not overwrite the first prep.

## Malformed Event

```bash
BAD_EVENT="$(mktemp /tmp/daymark-bad-event.XXXXXX.json)"
cat > "$BAD_EVENT" <<'JSON'
{"title":"Acme","startsAt":"soon","endsAt":"2026-07-01T15:00:00Z"}
JSON

! .build/arm64-apple-macosx/debug/daymark meeting-prep --root "$ROOT" --event-file "$BAD_EVENT"
```

Expected: command fails clearly with `invalid meeting event date: soon`.

## Rebuildable State

```bash
rm -rf "$ROOT/.daymark"
.build/arm64-apple-macosx/debug/daymark meeting-prep --root "$ROOT" --event-file "$EVENT"
```

Expected: dry-run still works from Markdown files. No cache or database state is required for correctness.
