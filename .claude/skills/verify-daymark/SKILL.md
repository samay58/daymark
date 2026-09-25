---
name: verify-daymark
description: Repo verification sequence for Daymark before a commit or ship. Use for "verify", "pre-commit check", "ship check", "is this ready to commit", or before ending a coding session in this repo.
---

# Verify Daymark

Run this in order. The order matters, see the stale-binary trap in step 3.

## 1. Text gate

Run `python3 ~/.claude/scripts/slopcheck.py <changed .md/prose files>` on every changed doc, comment, and prose string, then `git diff --check` for whitespace errors. Every closeout entry in `docs/PROGRESS.md` records both as required: "slopcheck passed for every changed source, test, and doc file" and "`git diff --check` clean."

## 2. Library tests

`swift package clean && swift test --skip CommandTests`. `CLAUDE.md`: "the canonical flow ... is: run the library suite with `swift test --skip CommandTests`."

## 3. CLI tests (the stale-binary trap)

`DaymarkCLITests` subprocess-launch a prebuilt `daymark` binary; `swift test --filter` alone will not rebuild it. `CLAUDE.md`: "`swift test --filter SomeCommandTests` does not rebuild `daymark` first and runs against a stale or missing binary."

1. `swift build --build-tests`
2. `swift build --product daymark`, so the prebuilt bundle has a current CLI to launch.
3. `xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest` (scope with `-XCTest DaymarkCLITests.<Class>,...` for a focused filter)

## 4. Product builds

`swift build --product daymark` and `swift build --product DaymarkApp`. `scripts/test.sh` runs steps 2 and 3 in order.

## 5. Read-only health check

`daymark doctor` (or `swift run daymark doctor`) against the real `~/phoenix`. `docs/PROGRESS.md`: "`daymark doctor` (read-only)." Never run mutating commands (`init`, `rebuild`, `rollover --apply`, `blocks refresh --apply`, `meeting-prep --apply`) against `~/phoenix` during verification.

## 6. Temp-workspace end-to-end pass

Exercise the changed command against a scratch directory only, via `--root <path>` or `DAYMARK_WORKSPACE_ROOT`, never `~/phoenix`. Follow the shape in `docs/PROGRESS.md` "Required Checks": dry-run first and confirm no write, apply and confirm one write, repeat apply and confirm no duplicate, then confirm behavior survives deleting `.daymark` and rebuilding.
