---
paths:
  - "backend/api/tests/**/*.php"
  - "backend/api/features/**/*.feature"
  - "apps/assisted_mobile/test/**/*.dart"
  - "apps/caregiver_mobile/test/**/*.dart"
  - "apps/wear_os/**/*.kt"
  - "apps/watchos/**/*Tests.swift"
---

# Testing Rules

- Keep automated line coverage at or above 90% when practical.
- Tests must prove behavior, contracts, edge cases, and regressions.
- Do not add shallow tests that only execute lines.
- Write tests in the same change as the behavior.
- If a change affects a public contract, cover the contract and the domain logic.
- If verification is skipped, report exactly why.

## Backend

- Unit-test handler/service behavior.
- Use integration tests when persistence or Symfony wiring is the risk.
- Use Behat for public HTTP behavior and important failure paths.
- Mock port interfaces, not Doctrine repositories.

## Flutter Apps

- Test service behavior, screen state, validation, storage migration, timeout,
  and error handling paths.
- For safety flows, test both success and cancellation/failure paths.
- Keep widget tests focused on user-visible behavior.

## Watch Apps

- Test fall threshold behavior, false-positive guardrails, and payload shape.
- Cover any user-controlled threshold setting that affects detection.

## Preferred Commands

```sh
make quality
make quality-api
make quality-assisted
make quality-caregiver
make quality-wear-os
make quality-watchos
```
