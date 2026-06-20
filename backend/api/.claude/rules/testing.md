---
paths:
  - "src/**/*.php"
  - "tests/**/*.php"
  - "features/**/*.feature"
---

# Testing Rules

## Mandatory delivery (every feature)

Every endpoint implementation is **incomplete** without at least one automated test for the changed behavior.

Write tests in the same session as the feature — never defer.

## Test matrix

- Pure domain logic change with no HTTP contract change:
  unit test in `tests/Unit/Domain/`; add integration test when persistence or wiring is the real risk
- New or changed API Platform endpoint:
  unit coverage for handler/service logic plus a Behat scenario for the happy path and key failure paths
- Messenger handler change:
  unit test in `tests/Unit/Domain/`; add integration test when the full dispatch/consume cycle is the real risk
- Port/Repository change:
  add `tests/Integration/` coverage when mocks would hide the real behavior

Rule: if a change affects both business logic and public HTTP behavior, cover both layers in the same session.

## Unit test rules

- Mock the **Port interface**, never the concrete Doctrine implementation
- Use intersection types for mock properties: `private FallAlertRepositoryInterface&MockObject $repository`
- Initialize mocks in `setUp()`, not inside individual test methods
- One test method per execution path: success + each exception path + edge cases
- Name: `test{Method}{Scenario}{Expected}` — e.g. `testInvokeWithUnknownDeviceThrowsNotFoundException`
- Never boot the HTTP kernel in a unit test (`extends TestCase`, not `WebTestCase`)
- No assertions = broken test — every test method must assert something

## Integration test rules

- Use `tests/Integration/` when persistence, repository behavior, or Symfony wiring needs real coverage
- Prefer integration tests for data-access behavior that unit mocks would hide

## Behat rules

- Context lives in `tests/Behat/ApiContext.php`
- Feature files live in `features/`
- Tag features with `@{domain}` (e.g. `@alert`, `@device`, `@caregiver`)
- Always include: happy-path scenario + relevant failure/edge-case scenario
- Steps that mutate DB state must be tagged `@database`
- Run a single scenario first: `vendor/bin/behat features/path.feature:LINE`
- If a new controller returns 500 in Behat, run `make cache-clear` before debugging further

## Preferred verification commands

- `make lint`
- `make analyse`
- `make rector`
- `make test`
- `make test-behat`
- `make test-unit` or `make test-integration` for targeted runs
