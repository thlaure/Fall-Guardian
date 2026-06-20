---
name: debug-quality
description: Use this skill whenever the user reports a PHPStan error, lint failure, Rector issue, PHPUnit test failure, or Behat scenario failure. Also trigger when the user pastes output from make analyse, make lint, make rector, make test, or make test-behat — or when they say things like "PHPStan complains about", "the test fails with", "Behat step not found", or "rector changed something".
version: 1.0.0
allowed-tools: Read, Grep, Glob, Bash, Edit
---

# Debug Quality Failures

Read the exact error first — don't guess. The error message and file path tell you everything. Never silence errors with suppressors or skip-flags; fix the root cause.

---

## PHPStan (make analyse)

**Read the error:** file path, line number, error message.

Common root causes and fixes:

| Error pattern | Likely cause | Fix |
|---|---|---|
| `... of null` | Method called on nullable without null check | Add guard or throw before the call |
| `Parameter #N ... expects X, Y given` | Wrong type passed | Fix the call site |
| `Method ... not found` | Typo, wrong class, or missing import | Fix the class reference |
| `Missing return type` | No return type hint | Add the return type |
| `Argument of type ... is not assignable` | Interface mismatch | Align types between interface and implementation |
| `Generic type ... is not specified` | Missing `@return array<T>` | Add the PHPDoc |

**Rules:**
- Fix at the source — never add `@phpstan-ignore` unless it's a confirmed false positive with no clean fix.
- Run `make analyse` after each fix to confirm the error is gone.

---

## Lint (make lint — PHP CS Fixer)

`make lint` auto-fixes almost everything. Run it first.

If errors remain after auto-fix:
- **Class name ≠ file name** — PHP requires `class Foo` to live in `Foo.php`.
- **Namespace mismatch** — the `namespace` declaration must match the directory path under `src/`.

Run `make lint` again after any manual fix to confirm.

---

## Rector (make rector)

`make rector` auto-applies fixes. Always review the diff before committing.

After rector changes: run `make lint && make analyse` to confirm nothing broke.

---

## PHPUnit (make test / make test-unit / make test-integration)

**Read the stack trace top-to-bottom.** The first frame inside your code is where the failure originates.

| Failure type | Likely cause | Fix |
|---|---|---|
| `Failed asserting that X is Y` | Wrong expected value or wrong handler logic | Fix the handler logic or assertion |
| `Expectation failed for method ... called N times` | Mock expectation doesn't match actual call count | Align `expects($this->once())` with actual usage |
| `Call to undefined method` | Mocking an interface but calling a method not on it | Add method to the Port interface |
| `No exception was thrown` | Handler should throw but didn't | Fix the handler condition |

**Rules:**
- Never comment out assertions — if an assertion fails, either the production code or the test expectation is wrong.
- Always mock the **Port interface**, never the concrete Doctrine repository.

---

## Behat (make test-behat)

**Read the failing step** — Behat shows the exact `.feature` line and context file.

| Failure type | Fix |
|---|---|
| `Undefined step` | Step text doesn't match any definition in `tests/Behat/`. Check for typos. |
| `404 Not Found` | Route missing or prefix wrong. Check `#[Route]` attribute on the controller. |
| `401 Unauthorized` | Missing device token auth in the context. |
| `422 Unprocessable Entity` | Payload is invalid. Check Input DTO constraints vs. what Behat sends. |
| `500 — not in container` | New controller not in dev cache. Run `make cache-clear`, then retry. |
| `500 Internal Server Error` | Unhandled exception. Run with `--verbose` to see it. |

After fixing, run the single failing scenario first:
```bash
vendor/bin/behat features/path/to/file.feature:LINE
```
Then run the full suite to confirm no regressions.
