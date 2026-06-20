---
paths:
  - "src/Domain/**/*.php"
---

# Domain Code Rules

- `declare(strict_types=1)` required in every file
- Prefer `final` and `readonly` where it fits; do not force them onto framework-integrated classes (State Processors, Handlers that are tagged services, etc.)
- Handlers are the primary home for application/business flow
- Prefer classes with a single clear responsibility
- Prefer constructor injection
- Domain services stay focused and explicit; prefer pure services (no I/O) when possible
- Prefer composition over inheritance for new domain behavior
- Prefer explicit use-case helpers, mappers, or factories over broad utility classes
- Prefer small typed DTOs over untyped arrays when the shape is reused or carries business meaning
- Port interfaces define the only legal dependency from domain to persistence — never import Doctrine classes inside `src/Domain/`
- No imports from another domain's internals — keep cross-domain dependency direction explicit
- State Processors and Controllers must never contain business logic; delegate to handlers or services
- Messenger Message classes must be simple data containers — no business logic, no service calls
- MessageHandlers must be thin orchestrators: fetch via Port, delegate to service, persist result

## Port interface naming

`src/Domain/{Feature}/Port/{Entity}RepositoryInterface.php`

Example: `src/Domain/Alert/Port/FallAlertRepositoryInterface.php`

## Current domains

`Alert`, `Caregiver`, `Contact`, `Device`, `Debug`, `Healthcheck`, `Push`

Match the local naming and folder conventions in the target domain.
