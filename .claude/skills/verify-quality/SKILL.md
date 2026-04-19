---
name: verify-quality
description: Use this skill when the user asks to run checks, validate a change, see whether code is ready, or investigate lint, analysis, test, or security-gate results in the Fall Guardian repository.
---

# Verify Quality

Use this skill to run the repository's real quality gates in a predictable order.

Read first:
- `AGENTS.md`
- `.claude/rules/testing.md`

Read as needed:
- `Makefile`
- `composer.json`

Workflow:
1. Discover the canonical commands exposed by the repository.
2. Prefer project wrappers such as `make` targets over raw vendor binaries.
3. Run the narrowest relevant tests first, then broader required checks.
4. Report failures with the command, affected area, and smallest likely fix direction.

Typical order:
1. `make check`
2. `cd flutter_app && flutter analyze`
3. `cd flutter_app && flutter test`
4. Add backend, native, or integration verification when the affected layer requires it

For targeted runs only, use the narrowest relevant command in the affected layer.

Rules:
- Do not invent substitute commands silently.
- If endpoint behavior changed, do not stop at unit tests only.
- If a change crosses Flutter/native/backend boundaries, do not stop at one layer's checks only.
