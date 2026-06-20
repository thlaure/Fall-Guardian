---
name: new-feature
description: Use this skill when the user asks to add or implement new functionality in fall_guardian_api. Trigger on requests like "add an endpoint", "implement this feature", "create this behavior", "implement a route", "add a route", "build this endpoint", or "implement this in [domain]".
---

# New Feature

Read first:
- `AGENTS.md`
- `.claude/rules/architecture.md`
- `.claude/rules/domain.md`
- `.claude/rules/testing.md`
- `.claude/rules/security.md`

Read as needed:
- `.claude/patterns.md`
- nearby files in the same domain

## Workflow

### Phase 1 — Acceptance criteria

1. If acceptance criteria are missing, ask for them before doing anything else.
2. Turn criteria into a numbered list of verifiable statements. Confirm with the user before proceeding.

### Phase 2 — Tests and deterministic checks

3. Prefer writing the Behat scenario(s) covering the happy path and key failure paths (not found, unauthorized, validation failure) before implementation when the public API behavior changes.
4. Prefer writing unit tests covering handler/service logic and each execution branch before implementation when the behavior is clear.
5. Run the narrowest relevant deterministic check when practical. A red test is useful only when it clarifies the expected behavior; do not stop the workflow just to demonstrate red/green ceremony.
6. Pause for user confirmation only when the acceptance criteria, API contract, schema change, or alert/push behavior is ambiguous or risky.

### Phase 3 — Implementation

7. Find the nearest local pattern in the target domain.
8. Reuse the surrounding folder and naming conventions.
9. Keep State Processors thin; Handlers own business flow.
10. Put the Port interface in `src/Domain/{Feature}/Port/`, implementation in `src/Infrastructure/Persistence/`.
11. If API Platform already covers the CRUD behavior cleanly, prefer that over extra domain layers.
12. Implement until all tests pass.
13. Run `make lint && make analyse && make rector` — fix any findings.
14. Run `make test && make test-behat` — all green before reporting done.

## Rules

- Deterministic tools are the first enforcement layer; prefer encoding repeatable rules there instead of relying on this skill.
- Hooks are the second layer for action-local safety checks.
- This skill is the third layer for architecture, testing strategy, and judgment-heavy workflow choices.
- Do not skip tests for behavior changes.
- Prefer readability over premature optimization.
- Do not introduce a conflicting structure inside the touched domain.
- If a criterion cannot be covered by an automated test, flag it explicitly.
