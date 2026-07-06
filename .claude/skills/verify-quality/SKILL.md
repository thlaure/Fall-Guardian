---
name: verify-quality
description: Use when the user asks to run the full quality gate, validate that changes are ready to ship, or asks "is this ready" / "run the checks" / "validate my changes". Proactive counterpart to debug-quality — use this before declaring work done, not after a failure is reported.
---

# Verify Quality

## Workflow

1. Identify every project touched by the current change (backend API,
   assisted app, caregiver app, Wear OS, watchOS).
2. Run the narrowest relevant check first, then the broader one, for each
   touched project:
   - API: `make -C backend/api quality`, then `make -C backend/api test`
     (add `make -C backend/api test-behat` if HTTP contract behavior changed)
   - Assisted app: `make quality-assisted`
   - Caregiver app: `make quality-caregiver`
   - Wear OS: `make quality-wear-os`
   - watchOS: `make quality-watchos`
3. If more than one project was touched, finish with `make quality` from the
   repo root to confirm nothing else regressed.
4. Report pass/fail per project. For any failure, name the command, the
   file, and the smallest likely fix — do not just paste raw output.

## Rules

- Prefer the project Makefile target over ad hoc tool invocations.
- If a command is unavailable in this environment (e.g. no Android/Xcode
  toolchain), say so explicitly instead of skipping silently.
- Fix the source issue instead of weakening quality config (PHPStan,
  analysis_options.yaml, lint rules). Treat loosening those as exceptional
  and ask first.
- Do not declare a task done while any touched project's quality gate is
  failing or unrun.
