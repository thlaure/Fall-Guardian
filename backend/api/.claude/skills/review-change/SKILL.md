---
name: review-change
description: Use this skill when the user asks for a review, a correctness pass, or wants to check whether a fall_guardian_api change follows project conventions. Also trigger on phrases like "review my code", "review this", "is this correct", "check this implementation", "does this follow the conventions", or "look at what I did".
---

# Review Change

Read first:
- `AGENTS.md`
- `.claude/rules/architecture.md`
- `.claude/rules/domain.md`
- `.claude/rules/testing.md`
- `.claude/rules/security.md`

Read as needed:
- `.claude/patterns.md`
- the relevant diff and nearby files

Workflow:
1. Inspect the diff or requested scope.
2. Check architecture and domain-boundary rules (Port interfaces, Infrastructure separation).
3. Check validation, persistence boundaries, and error handling consistency.
4. Check test completeness for the changed behavior.
5. Check whether the change is likely to pass the repository quality gates.

Rules:
- Focus on correctness, security, regressions, and missing tests.
- Do not focus on style nits already covered by tooling unless they expose real risk.
