# Agent Guide

This repository contains the Fall Guardian native Wear OS app.

Also follow the workspace-level guide at `../../AGENTS.md` when working from this project.

`CLAUDE.md` must stay a thin pointer to this file.

## Project

- Native Android Wear OS app for fall detection and watch-side alert handling
- Keep sensor/fall detection code explicit and testable
- Keep phone/backend communication boundaries narrow and easy to review

## Engineering Rules

Always:

- keep watch-to-phone and watch-to-backend contracts aligned with the assisted app and backend
- keep Gradle, Android Studio, and local SDK generated files out of Git
- prefer readable, explicit code over clever Android/Wear OS platform tricks
- add concise comments for Wear OS concepts, sensors, foreground services, wake locks, permissions, background message delivery, and safety-critical alert behavior when they are not obvious to a non-mobile developer
- keep automated line coverage at or above 90%; coverage must come from useful behavior, contract, edge-case, and regression tests, not shallow line execution
- run relevant Gradle checks after Kotlin/Java or Android configuration changes when feasible

Ask first:

- adding Gradle dependencies or Android plugins
- changing package ID, signing, permissions, sensors, foreground service behavior, or deployment targets
- changing fall detection thresholds or alert handoff behavior

Never:

- hardcode API secrets, tokens, or local machine paths
- hide important fall-detection workflow in framework entrypoints

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
make check
```
