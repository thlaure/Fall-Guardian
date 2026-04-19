# Agent Guide

Canonical agent instructions for this repository live in this file.

`CLAUDE.md` must stay a thin pointer to `AGENTS.md` so Claude and Codex share one source of truth.

## Read First

- `PROJECT_CONTEXT.md`
- `WORKFLOW.md`
- `CURRENT_STATUS.md`

## Project

- Cross-platform fall detection and alerting app
- Flutter phone app, native watch apps, Symfony/API Platform backend
- Primary workflows: watch fall detection, phone alert orchestration, backend-owned escalation, caregiver notification delivery

## Architecture

- Use clean architecture and ports/adapters pragmatically
- Keep `AlertCoordinator` as the phone-side workflow owner
- Keep Flutter widgets UI-only
- Keep native bridges thin and focused on transport/runtime integration
- Keep backend workflow in application services and Messenger handlers
- If a native framework or API Platform feature already solves the need cleanly, use it instead of forcing extra abstraction

Current rule for this project:

- phone alert flow stays explicit and coordinator-driven
- watch implementations stay native
- backend alert delivery stays service-driven, not controller-driven
- cross-platform contracts must remain aligned across Flutter, Android, iOS, Wear OS, watchOS, and backend

## Current Flow

- `watch detects fall -> watch countdown starts -> phone receives shared timestamp -> AlertCoordinator owns phone workflow -> timeout submits to backend -> backend dispatches escalation`

## Repository Structure

```text
fall_guardian/
├── flutter_app/
├── wear_os_app/
├── watchos_app/
└── backend/
```

## Engineering Rules

Always:

- keep `declare(strict_types=1);` in PHP
- prefer explicit naming
- write tests for behavior changes
- run verification after changes
- preserve backend API prefix `/api/v1`
- prefer readability and reviewability over premature optimization
- if framework-native behavior is already clean, use it instead of layering for its own sake
- prefer fixing static-analysis issues in code, types, or PHPDoc instead of weakening config

Ask first:

- adding packages or plugins
- changing database schema in risky or irreversible ways
- changing the backend delivery strategy
- changing major cross-platform contracts
- changing `phpstan.neon`, CI policy, or release workflow
- running `git commit`
- running `git push`

Never:

- commit directly to `master`, `main`, or `develop`
- hardcode secrets
- put workflow logic in widgets, controllers, or framework entrypoints
- create duplicated instructions across `AGENTS.md` and `CLAUDE.md`
- run `git commit` or `git push` silently; always ask for confirmation in the current conversation first

## Shared `.claude` Assets

Claude and Codex must both use the repo-local `.claude/` folder as shared operational guidance.

Use these files as the common behavior layer:

- `.claude/settings.json`
- `.claude/rules/architecture.md`
- `.claude/rules/testing.md`
- `.claude/rules/security.md`
- `.claude/patterns.md`

Use the matching workflow when the task fits:

- scan or inspect repository work: `.claude/skills/scan-project/SKILL.md` or `.claude/commands/fall-guardian/scan-project.md`
- new functionality: `.claude/skills/new-feature/SKILL.md` or `.claude/commands/fall-guardian/new-feature.md`
- bug fixing: `.claude/skills/bug-fix/SKILL.md` or `.claude/commands/fall-guardian/bug-fix.md`
- general review: `.claude/skills/review-change/SKILL.md` or `.claude/commands/fall-guardian/review-change.md`
- security review: `.claude/skills/security-review/SKILL.md` or `.claude/commands/fall-guardian/security-review.md`
- verification and checks: `.claude/skills/verify-quality/SKILL.md` or `.claude/commands/fall-guardian/verify-quality.md`
- commit preparation: `.claude/skills/prepare-commit/SKILL.md` or `.claude/commands/fall-guardian/prepare-commit.md`
- instruction improvement: `.claude/skills/improve-instructions/SKILL.md` or `.claude/commands/fall-guardian/improve-instructions.md`
- build-in-public post drafting: `.claude/skills/propose-posts/SKILL.md` or `.claude/commands/fall-guardian/propose-posts.md`
- production-urgency fixes: `.claude/skills/hotfix/SKILL.md` or `.claude/commands/fall-guardian/hotfix.md`
- execution discipline for review, refactor, or ambiguity-heavy tasks: `.claude/skills/karpathy-guidelines/SKILL.md`

Use the Flutter/Dart-specific workflow when the task is mainly in the phone app:

- scan Flutter architecture: `.claude/skills/flutter-scan-project/SKILL.md` or `.claude/commands/flutter/scan-project.md`
- Flutter feature work: `.claude/skills/flutter-new-feature/SKILL.md` or `.claude/commands/flutter/new-feature.md`
- Flutter bug fixing: `.claude/skills/flutter-bug-fix/SKILL.md` or `.claude/commands/flutter/bug-fix.md`
- Flutter review: `.claude/skills/flutter-review-change/SKILL.md` or `.claude/commands/flutter/review-change.md`
- Flutter security review: `.claude/skills/flutter-security-review/SKILL.md` or `.claude/commands/flutter/security-review.md`
- Flutter verification: `.claude/skills/flutter-verify-quality/SKILL.md` or `.claude/commands/flutter/verify-quality.md`

Guidance:

- skills and commands are two interfaces for the same workflows; do not let them drift
- prefer skills when the user is speaking naturally
- prefer commands when the user explicitly invokes a named workflow
- rules and patterns are the shared source of truth behind both interfaces
- `.claude/settings.json` is the versioned repository-default settings file for both Claude and Codex
- `.claude/settings.local.json` is only for optional local overrides and must not be treated as the shared team standard

## Instructions Improvement Policy

Instruction files are living documentation and should improve with the project and environment, but only through an explicit proposal-and-confirmation workflow.

Files in scope:

- `AGENTS.md`
- `CLAUDE.md`
- `.claude/rules/*.md`
- `.claude/patterns.md`
- `.claude/hooks/guardrails.py`
- `.claude/commands/fall-guardian/*.md`
- `.claude/commands/flutter/*.md`
- `.claude/skills/*/SKILL.md`

Policy:

- instructions may be improved when there is durable evidence of drift
- examples of drift:
  - repeated corrections or reviewer comments
  - repo-structure or workflow changes
  - architecture or testing conventions that changed in practice
  - duplicated or conflicting guidance
- only reusable, stable guidance should be added
- temporary context, one-off fixes, and local anecdotes should not be added to instruction files
- changes to instruction files must be proposed first and applied only after explicit confirmation in the current conversation

## Quality Gates

Run when relevant:

- `make check`
- `cd flutter_app && flutter analyze`
- `cd flutter_app && flutter test`
- `cd backend && vendor/bin/phpstan analyse --no-progress --memory-limit=-1`
- `cd backend && vendor/bin/phpunit --testsuite=Unit`

Preferred broader verification:

- `make check`
- `cd backend && docker compose -f docker-compose.yml exec -T app vendor/bin/phpstan analyse --no-progress --memory-limit=-1`
- `cd backend && docker compose -f docker-compose.yml exec -T app vendor/bin/phpunit --testsuite=Integration`

## Testing Notes

- Flutter tests: `flutter_app/test`
- Wear OS tests: `wear_os_app` Gradle test targets
- Backend unit tests: `backend/tests/Unit`
- Backend integration tests: `backend/tests/Integration`
- PHPUnit method names must stay camelCase

## Documentation Policy

Use this split:

- `README.md`: human-facing project overview and usage
- `PROJECT_CONTEXT.md`: canonical shared architecture and invariants
- `WORKFLOW.md`: runtime behavior and product flow
- `CURRENT_STATUS.md`: temporary limitations and active warnings
- `AGENTS.md`: canonical agent instructions
- `CLAUDE.md`: pointer file only

If agent instructions need to change:

1. update `AGENTS.md`
2. keep `CLAUDE.md` minimal and referential
3. update project docs only when human-facing behavior or workflow changed
