---
name: prepare-commit
description: Use this skill when the user says "prepare commit", "prepare a commit", "commit", asks to stage files, write a commit message, or prepare PR notes for fall_guardian_api. Trigger proactively — do not handle commit preparation manually.
---

# Prepare Commit

Read first:
- `AGENTS.md`
- `Makefile`

Read as needed:
- `git status`
- `git diff`
- `git log`

## Workflow

1. Inspect the current branch and working tree.
2. Stage only the intended files with `git add`.
3. Run relevant quality checks before proposing the commit.
4. If the current branch is protected, create a dedicated branch first — confirm branch name with user.
5. Write the commit message using Conventional Commits format (see below).
6. Ask for explicit confirmation before running `git commit`.
7. Ask for explicit confirmation before running `git push`.

## Commit format

```
{type}({scope}): {description}
```

| Type | When to use |
|---|---|
| `feat` | New endpoint, handler, domain feature, push delivery path |
| `fix` | Bug fix in existing behaviour |
| `refactor` | Code restructuring with no behaviour change |
| `test` | Adding or fixing tests |
| `docs` | Documentation only |
| `chore` | Build, config, dependency, Docker changes |
| `perf` | Performance improvement |

**Scope** — domain name in snake_case matching `src/Domain/` folder: `alert`, `caregiver`, `device`, `push`, `healthcheck`. Omit if change spans multiple domains.

**Description rules** — imperative mood, lowercase, no period, under 72 chars total on first line.

```
feat(alert): add cancel fall alert endpoint
fix(caregiver): handle missing push token on invite
test(device): add unit tests for device registration handler
chore: update docker compose healthcheck for messenger
```

## Branch naming

```
{type}/{short-description}
```

Examples: `feat/cancel-fall-alert`, `fix/missing-push-token`

## Rules

- Never commit or push silently — always ask for confirmation.
- One logical change per commit — no bundling unrelated fixes.
- Run `make lint` first; if it modifies files, stage those too.
- If pre-commit checks find blockers, report before proposing the commit.
