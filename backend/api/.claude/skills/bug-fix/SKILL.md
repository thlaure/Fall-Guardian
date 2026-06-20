---
name: bug-fix
description: Use this skill when the user reports broken behavior, regressions, failing tests, or asks to fix a bug in fall_guardian_api. Also trigger on phrases like "it's not working", "this is broken", "fix this", "something is wrong with", or "why does this fail".
---

# Bug Fix

Read first:
- `AGENTS.md`
- `.claude/rules/architecture.md`
- `.claude/rules/testing.md`
- `.claude/rules/security.md`

Read as needed:
- `.claude/patterns.md`
- nearby files in the failing path

Workflow:
1. Reproduce the issue.
2. Isolate the narrowest failing path.
3. Identify the root cause before editing.
4. Implement the smallest clear fix.
5. Add or update a regression test.
6. Run the relevant verification commands.

Rules:
- Reuse the local domain pattern.
- Prefer readability over performance unless there is a measured bottleneck.
