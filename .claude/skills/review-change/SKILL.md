---
name: review-change
description: Use when the user asks for a review, correctness pass, PR review, or convention check for any Fall Guardian project.
---

# Review Change

Read first:

- `AGENTS.md`
- project-local `AGENTS.md` for touched projects
- `.claude/rules/architecture.md`
- `.claude/rules/testing.md`
- `.claude/rules/security.md`

Workflow:

1. Inspect the diff or requested scope.
2. Identify touched projects and contracts.
3. Check correctness, regressions, security, tests, and readability.
4. Check whether the relevant quality gates were run.
5. Report findings first, ordered by severity, with file paths.

Do not spend review budget on style nits already covered by deterministic tools.
