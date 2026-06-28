# Parking Lot

Good ideas that are not part of the current milestone belong here.

## Later

- App-bundle Xcode project with signing and UI test scheme.
- Menu bar helper.
- Global hotkey implementation.
- Calendar connector.
- Gmail connector.
- Embeddings.
- Cloud sync.
- iOS capture companion.
- Arbitrary dynamic block plugin system.

## Milestone 1 follow-ups

- Vault coexistence: resolved. The default workspace is `~/phoenix`, because operating on the vault is the point. Bootstrap is additive and never touches the existing 01-active through 04-knowledge-base trees. ADR-005 was reversed to record this. `DAYMARK_WORKSPACE_ROOT` and the Settings field still override it.
- Git: initialized on 2026-06-28 with a `.gitignore` for build artifacts. Future parallel sessions should branch per worktree rather than share one tree.
