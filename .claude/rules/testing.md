---
paths:
  - "backend/src/**/*.php"
  - "backend/tests/**/*.php"
  - "backend/features/**/*.feature"
  - "flutter_app/lib/**/*.dart"
  - "flutter_app/test/**/*.dart"
  - "caregiver_app/lib/**/*.dart"
  - "caregiver_app/test/**/*.dart"
---

# Testing Rules

- Tests are part of delivery, not follow-up work.
- Bug fixes should ship with a regression test whenever the behavior can be reproduced in an automated way.
- If behavior changes and no test is added or updated, explain why explicitly.
- Run the narrowest relevant tests first, then broader repository checks.

## Backend Test Matrix

- Pure backend domain logic change with no HTTP contract change: unit test required.
- Backend handler/service change: unit test the success path and relevant failure/idempotency paths.
- Backend endpoint contract change: add or update HTTP-level coverage in `backend/tests/Integration` and/or `backend/features`.
- Backend persistence, repository, Messenger, or service wiring change: add or update integration/Behat coverage when mocks would hide the real risk.
- API Platform resource/processor/provider change: cover serialization, validation, auth, and contract behavior at API level when relevant.
- Safety-critical alert, cancel, escalation, caregiver-link, or notification-delivery behavior: cover both happy path and at least one failure or negative path.

Current backend suites:

- `backend/tests/Unit/Domain` for domain handlers/services
- `backend/tests/Unit/Infrastructure` for focused adapter behavior
- `backend/tests/Integration` for API/persistence/wiring behavior
- `backend/tests/Behat` for Behat contexts
- `backend/features` for end-to-end API scenarios

Backend test style:

- Mock repository or gateway interfaces, not concrete adapters.
- Use intersection types for mock properties: `private FeatureRepositoryInterface&MockObject $repository`.
- Initialize reusable mocks in `setUp()`.
- Keep PHPUnit method names camelCase.
- Unit tests must not boot the HTTP kernel; use `TestCase`, not `WebTestCase`.
- Every test method must assert behavior or expectations.
- Prefer one test per execution path: success, validation/invalid input, not found, forbidden, idempotency, and edge cases where relevant.

Backend verification commands:

- `cd backend && vendor/bin/phpunit --testsuite=Unit`
- `cd backend && vendor/bin/phpunit --testsuite=Integration`
- `cd backend && vendor/bin/behat --config behat.yaml.dist --colors`
- `cd backend && vendor/bin/phpstan analyse --no-progress --memory-limit=-1`
- `cd backend && vendor/bin/php-cs-fixer fix --dry-run --diff --verbose --sequential`

## Flutter And Native

- Flutter coordinator/repository behavior should have unit tests.
- Flutter UI behavior should use widget tests when view behavior changes.
- Native platform tests are expected when platform-only behavior is touched and testable in the local tooling.
- When alert-flow behavior changes, review and test the affected Flutter, native bridge, watch, and backend surfaces together.
