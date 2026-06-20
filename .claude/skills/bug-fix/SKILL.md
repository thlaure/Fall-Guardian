---
name: bug-fix
description: Use when the user reports broken behavior, regressions, failing tests, runtime errors, or asks to fix a bug in any Fall Guardian project.
---

# Bug Fix

Workflow:

1. Reproduce or inspect logs/tests to understand the failure.
2. Identify the owning project and read its `AGENTS.md`.
3. Fix the smallest behavior-owning surface.
4. Add or update regression tests.
5. Run the relevant project quality command.
6. Report the cause, fix, and verification.
