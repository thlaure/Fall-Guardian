# Fall Guardian — Codex Instructions

Read these first:
- `PROJECT_CONTEXT.md`
- `WORKFLOW.md`
- `CURRENT_STATUS.md`

## Codex-specific expectations

- Treat `PROJECT_CONTEXT.md` as the shared architecture source of truth.
- Keep changes architecture-first: workflow in coordinators/services, UI in widgets, platform details in adapters.
- When changing safety-critical behavior, prefer concrete code changes plus verification over speculative notes.
- When changing cross-platform contracts, inspect Flutter, Android, iOS, Wear OS, and watchOS before concluding the work is complete.
- Run `make check` before close-out.
- Use Conventional Commits.
- When opening a PR, include a summary and a manual verification checklist.

## Codex review standard

When reviewing or refactoring:
- prioritize correctness, regressions, lifecycle safety, and platform parity
- call out real findings before summaries
- do not leave duplicated logic across Flutter/native layers when a clearer ownership boundary is possible

## Codex change checklist

- Alert flow changed:
  - review `AlertCoordinator`
  - review both native phone bridges
  - review both watch implementations
  - update tests
  - update `WORKFLOW.md` if behavior changed
- Persistence/security changed:
  - review migration path
  - review secure storage path
  - review tests
- Opening a PR:
  - describe what changed
  - describe what remains limited or risky
  - include a checklist of what should be manually checked
