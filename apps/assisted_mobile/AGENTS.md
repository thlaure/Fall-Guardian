# Agent Guide

This repository contains the Fall Guardian assisted user Flutter mobile app.

Also follow the workspace-level guide at `../../AGENTS.md` when working from this project.

`CLAUDE.md` must stay a thin pointer to this file.

## Project

- Flutter app for the assisted user phone experience
- Owns assisted user alert orchestration, watch communication, emergency contacts, and API interaction from the phone
- Keep widgets UI-only and keep workflow logic in services/coordinators

## Engineering Rules

Always:

- keep cross-platform contracts aligned with the backend, Wear OS app, watchOS app, and caregiver app
- keep generated Flutter/iOS/Android files out of Git unless they are intentionally source-controlled by Flutter
- prefer readable, explicit code over clever Flutter/platform tricks
- add concise comments for mobile/platform concepts, async flows, native bridges, permissions, background execution, and safety-critical alert behavior when they are not obvious to a non-mobile developer
- keep automated line coverage at or above 90%; coverage must come from useful behavior, contract, edge-case, and regression tests, not shallow line execution
- enforce the 90% coverage gate on behavior code through `make quality`; UI rendering, localization text, and thin platform-plugin wrappers may be excluded from the threshold when their useful behavior is covered elsewhere
- run `flutter analyze` after Dart changes when feasible
- run `flutter test` for behavior changes when tests exist or are added

Ask first:

- adding Flutter packages or native plugins
- changing bundle IDs, Firebase config, signing, entitlements, or deployment targets
- changing backend API contracts or alert workflow behavior

Never:

- hardcode API secrets, tokens, or production-only local values
- put workflow logic directly in Flutter widgets

## Shared `.claude` Assets

Claude and Codex must both use the monorepo root `.claude/` folder as shared operational guidance.

Use these files as the common behavior layer:

- `../../.claude/settings.json`
- `../../.claude/rules/architecture.md`
- `../../.claude/rules/security.md`
- `../../.claude/rules/testing.md`
- `../../.claude/patterns.md`
- `../../.claude/agents/qa-reviewer.md`
- `../../.claude/agents/security-reviewer.md`
- `../../.claude/hooks/*.py`

Use the matching workflow when the task fits:

- new functionality: `../../.claude/skills/new-feature/SKILL.md`
- bug fixing: `../../.claude/skills/bug-fix/SKILL.md`
- review: `../../.claude/skills/review-change/SKILL.md`
- security review: `../../.claude/skills/security-review/SKILL.md`
- commit preparation: `../../.claude/skills/prepare-commit/SKILL.md`
- quality/debugging failures: `../../.claude/skills/debug-quality/SKILL.md`
- execution discipline for review, refactor, or ambiguity-heavy tasks: `../../.claude/skills/karpathy-guidelines/SKILL.md`
- acceptance-criteria verification: `../../.claude/agents/qa-reviewer.md`
- independent security review: `../../.claude/agents/security-reviewer.md`

## Instructions Improvement Policy

Files in scope: `AGENTS.md`, `CLAUDE.md`.

- instructions may be improved when there is durable evidence of drift
- only reusable, stable guidance should be added
- examples of drift: repeated corrections, dependency or project-structure changes, conventions that changed in practice, duplicated or conflicting guidance
- temporary context, one-off fixes, and local anecdotes must not be added
- changes must be proposed first and applied only after explicit confirmation in the current conversation

## Verification

Common commands:

```sh
make quality
make build-android
make build-ios
```
