# Claude Guide

Canonical agent instructions for this repository live in this file.

Also follow the workspace-level guide at `../../CLAUDE.md` when working from
this project.

## Project

- Fall detection and alerting backend API
- PHP 8.5, Symfony 7.4, API Platform 4.2, PostgreSQL via Doctrine ORM, FrankenPHP, Redis, Symfony Messenger
- Main business domains in `src/Domain/`: `Alert`, `Caregiver`, `Contact`, `Device`, `Debug`, `Healthcheck`, `Push`
- Primary workflows: device registration, fall alert ingestion, push escalation via Messenger, caregiver invite/link management
- Auth: custom device token authenticator — no Keycloak or session auth

## Architecture

Use these principles pragmatically:

- new business features belong in `src/Domain/<Feature>/...`
- keep API Platform resources, State Processors/Providers, Handlers, Messages, and Ports close to the domain they serve
- keep State Processors and Controllers focused on HTTP/API Platform orchestration
- keep Handlers as the main place for application/business flow
- keep Port interfaces (`src/Domain/<Feature>/Port/`) as the boundary between domain and infrastructure
- keep Doctrine implementations in `src/Infrastructure/Persistence/`
- keep HTTP security in `src/Infrastructure/Http/Security/`
- keep external push integrations in `src/Infrastructure/Push/`
- keep Doctrine entities focused on ORM mapping and simple state transitions
- keep DTOs, Request objects, and Response objects free of business decisions
- if API Platform already provides a clean solution for a CRUD/read concern, prefer it over adding unnecessary domain layers

Current repository shape:

```text
src/
├── Domain/
│   ├── Alert/{Handler,Message,Port,Processor,Provider,Request,Response,Service}
│   ├── Caregiver/{Handler,Port,Request,Response,Service}
│   ├── Contact/{Handler,Port,Request,Response}
│   ├── Device/{Handler,Port,Request,Response,Service}
│   ├── Debug/Controller
│   ├── Healthcheck/Controller
│   └── Push/Port
├── Entity/
├── Enum/
└── Infrastructure/
    ├── Http/Security/
    ├── Persistence/
    └── Push/
```

Flow patterns:

- API Platform write flow: `ApiResource DTO -> State Processor -> Handler/Service -> Port/Repository -> Entity`
- API Platform read flow: `ApiResource View -> State Provider -> Repository/Service -> View DTO`
- Controller flow: `Controller -> request params/body -> Handler -> Port/Repository -> Response`
- Messenger flow: `Message -> MessageHandler -> Port/Service/Gateway -> persisted state`

Rules:

- preserve API prefix `/api/v1`
- routes are discovered from `src/Domain/`
- do not introduce top-level `src/DTO/`, `src/Handler/`, or `src/Repository/` layers
- prefer extending the local domain folder pattern over introducing a new layout
- backend-owned alert escalation and push delivery must remain handler/service-driven, not controller-driven

## Design Principles

- prefer Clean Architecture directionally: business flow in handlers/services, frameworks and persistence at the edges, boundaries explicit
- apply SOLID as a review heuristic, not as a reason to multiply abstractions
- prefer single-purpose classes and explicit dependency direction
- depend on abstractions (Port interfaces) when it materially improves testability or replaceability
- prefer composition over inheritance for new behavior unless the surrounding code already uses inheritance intentionally
- prefer simple, readable, explicit code over clever abstractions
- delete unnecessary complexity when touching code

## Repository Structure — Port + Infrastructure Pattern

Domain port interfaces live inside the domain:

```
src/Domain/{Feature}/Port/{Feature}RepositoryInterface.php
```

Doctrine implementations live in Infrastructure:

```
src/Infrastructure/Persistence/Doctrine{Feature}Repository.php
```

Bind the interface in `config/services.yaml`:

```yaml
App\Domain\{Feature}\Port\{Feature}RepositoryInterface:
    class: App\Infrastructure\Persistence\Doctrine{Feature}Repository
```

## Engineering Rules

Always:

- keep `declare(strict_types=1);` in PHP
- prefer explicit naming
- write tests for behavior changes
- keep automated line coverage at or above 90%; coverage must come from useful behavior, contract, edge-case, and regression tests, not shallow line execution
- run verification after changes
- preserve API prefix `/api/v1`
- prefer readability and reviewability over premature optimization
- prefer fixing PHPStan issues in code, types, or PHPDoc instead of weakening `phpstan.neon`

Ask first:

- adding composer packages
- changing database schema in risky or irreversible ways
- changing the push delivery strategy or alert escalation flow
- changing major API contracts
- changing `phpstan.neon` or CI policy
- running `git commit`
- running `git push`

Never:

- commit directly to `master`, `main`, or `develop`
- hardcode secrets or push credentials
- put workflow logic in State Processors, Controllers, or API resources
- duplicate instructions between this file and the shared `.claude/` rules — link, don't repeat
- run `git commit` or `git push` silently; always ask for confirmation first

## Guardrail Enforcement Priority

Project rules should be enforced in this order:

1. Deterministic tools: PHP CS Fixer, PHPStan, Rector, PHPUnit, Behat, GrumPHP, dependency security checks, Symfony compiler/container checks, and other repeatable project commands.
2. Agent hooks: lightweight safety checks that must run around agent actions, such as credential detection, PHP syntax checks, protected branch checks, and write-scope checks.
3. Skills and written guidance: architecture, Clean Architecture, SOLID, CQRS-style separation, testing strategy, review workflows, and other rules that need human/agent judgment.

When a rule is repeatable and machine-checkable, encode it in a deterministic tool before documenting it as guidance. Use hooks for immediate action boundaries only. Use skills for judgment-heavy workflows and conventions that tools cannot check reliably.

## Testing Notes

Current suites and locations:

- `tests/Unit/Domain/` for domain unit tests
- `tests/Integration/` for integration coverage
- `tests/Behat/` for Behat contexts
- `features/` for Behat feature files

Endpoint test expectations:

- maintain at least 90% line coverage for the repository when practical; if coverage drops below target, either add meaningful tests or explain why the uncovered path is not useful to test automatically
- new or changed pure domain logic with no HTTP contract change: unit test required; add integration test when persistence or wiring is the real risk
- new or changed API Platform endpoint: unit test for handler/service logic plus Behat scenario covering the happy path and key failure paths
- Messenger handler changes: unit test required; add integration test when the full dispatch/consume cycle is the real risk
- Port/Repository changes: add integration coverage when mocks would hide the real behavior

Preferred verification commands:

- `make lint`
- `make analyse`
- `make rector`
- `make test`
- `make test-behat`

Container runtime:

- use Makefile targets instead of calling `docker compose` or `podman compose` directly when a target exists
- the Makefile selects `podman compose` when Podman is installed and falls back to `docker compose`
- override the runtime explicitly with `COMPOSE="docker compose"` or `COMPOSE="podman compose"` only when needed

## Documentation Policy

Use this split:

- `README.md`: human-facing project overview and usage
- `CLAUDE.md`: canonical agent instructions

If agent instructions need to change:

1. update `CLAUDE.md`
2. update `README.md` only for human-facing behavior or workflow changes
