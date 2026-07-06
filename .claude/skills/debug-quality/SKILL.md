---
name: debug-quality
description: Use when the user reports a formatter, linter, static analysis, test, build, CI, or coverage failure in any Fall Guardian project. See verify-quality for the proactive counterpart, run before declaring work done rather than after a failure.
---

# Debug Quality

Workflow:

1. Read the failing command output and identify the owning project.
2. Prefer the project Makefile target over ad hoc commands.
3. Fix the source issue instead of weakening quality config.
4. Re-run the smallest failing target.
5. Re-run the relevant project quality command before finishing.

Common targets:

- API: `make quality-api`, `make -C backend/api test`,
  `make -C backend/api test-behat`
- Assisted app: `make quality-assisted`
- Caregiver app: `make quality-caregiver`
- Wear OS: `make quality-wear-os`
- watchOS: `make quality-watchos`
