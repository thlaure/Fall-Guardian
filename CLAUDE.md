# Fall Guardian — Claude Instructions

Read these first:
- `PROJECT_CONTEXT.md`
- `WORKFLOW.md`
- `CURRENT_STATUS.md`

## Claude-specific expectations

- Use `PROJECT_CONTEXT.md` for architecture and invariants, not this file.
- Keep responses and plans aligned with the current implementation, not outdated product assumptions.
- When suggesting or making changes, preserve clean dependency direction and avoid increasing Flutter/native duplication.
- Treat cross-platform drift as a primary risk.

## Claude review standard

- Evaluate product requirements, implementation status, and platform constraints separately.
- When identifying a gap, distinguish:
  - required behavior
  - current implementation
  - known platform limitation

## Claude change checklist

- If changing alert behavior:
  - review Flutter workflow ownership
  - review native Android/iOS bridge behavior
  - review watch cancel/sync behavior
  - update tests
  - update `WORKFLOW.md` if behavior changed
