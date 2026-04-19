Perform a structured code review for a Fall Guardian change.

Review scope: `$ARGUMENTS`

If the scope is omitted, inspect the current git diff.

Review checklist:
1. Confirm the change respects the repository architecture and `AGENTS.md`.
2. Check that widgets, controllers, and framework entrypoints remain orchestration-only.
3. Check that business rules stay in the owning layer: coordinator, native bridge adapter, handler, use-case, or domain service.
4. Check validation at the input boundary.
5. Check persistence code for leaked business logic.
6. Check cross-platform contract alignment when Flutter/native/backend integrations changed.
7. Check error handling and API behavior consistency.
8. Check test completeness for the changed behavior.
9. Check that the change can pass the repo quality gates.

Prioritize findings:
- correctness bugs
- security regressions
- architectural regressions
- missing validation or tests
- maintainability issues

Response format:
- findings first, ordered by severity
- then open questions or assumptions
- then a short summary only if useful

Do not focus on style nits already covered by formatters or static analysis unless they expose real risk.
