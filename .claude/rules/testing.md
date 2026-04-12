# Testing Rules

- Tests are part of delivery, not follow-up work.
- Bug fixes should ship with a regression test whenever the behavior can be reproduced in an automated way.
- Choose test scope based on the changed behavior:
  - Flutter unit/widget tests for coordinator, repositories, and UI behavior
  - native platform tests where platform-only behavior is touched
  - backend unit tests for handlers/services and integration tests for API/persistence behavior
- When endpoint or alert-flow behavior changes, cover both happy path and at least one failure path.
- Keep test naming consistent with the repository convention.
- Run the narrowest relevant tests first, then the broader repository checks.
- If a behavior changes and no test is added or updated, explain why explicitly.
