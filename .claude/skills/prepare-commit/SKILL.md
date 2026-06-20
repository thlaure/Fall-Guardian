---
name: prepare-commit
description: Use this skill when the user says "prepare commit", "prepare a commit", "commit", asks to stage files, write a commit message, or prepare PR notes for Fall Guardian. Trigger proactively; do not handle commit preparation manually.
---

# Prepare Commit

Read first:

- `AGENTS.md`
- `README.md`
- project-local `AGENTS.md` for every touched project
- relevant Makefile targets

Read as needed:

- `git status --short --branch`
- `git diff`
- `git log --oneline`

## Workflow

1. Inspect the current branch and working tree.
2. Identify every touched project and separate unrelated changes.
3. Stage only the intended files with `git add`.
4. Run the relevant deterministic checks before proposing the commit.
5. If the current branch is protected, create a dedicated branch first.
6. Write the commit message using Conventional Commits format.
7. Ask for explicit confirmation before `git commit` unless the user already
   explicitly asked to commit.
8. Ask for explicit confirmation before `git push` unless the user already
   explicitly asked to push.

## Commit Format

```text
{type}({scope}): {description}
```

Types:

- `feat`: new user-facing or API behavior
- `fix`: bug fix in existing behavior
- `refactor`: code restructuring with no behavior change
- `test`: adding or fixing tests
- `docs`: documentation only
- `chore`: build, config, dependency, CI, or tooling changes
- `perf`: performance improvement

Scopes:

- `api`
- `assisted`
- `caregiver`
- `wear-os`
- `watchos`
- `monorepo`
- specific backend domains when useful, such as `alert`, `caregiver`,
  `device`, or `push`

Rules:

- imperative mood
- lowercase description
- no trailing period
- first line under 72 characters when practical

Examples:

```text
feat(caregiver): list protected persons before add action
fix(api): rate limit invite acceptance
test(assisted): cover cancelled alert history sync
docs(monorepo): expand project readmes
chore(monorepo): centralize claude settings
```

## Branch Naming

```text
{type}/{short-description}
```

Examples:

```text
feat/protected-persons-list
fix/firebase-secret-config
docs/project-readmes
chore/shared-claude-config
```

## Verification Matrix

- API touched: `make quality-api`; add `make -C backend/api test` and
  `make -C backend/api test-behat` for behavior/API changes.
- Assisted app touched: `make quality-assisted`.
- Caregiver app touched: `make quality-caregiver`.
- Wear OS touched: `make quality-wear-os`.
- watchOS touched: `make quality-watchos`.
- Cross-project contract touched: run every affected project check.

## Rules

- One logical change per commit.
- Do not bundle unrelated repo cleanup with feature/fix work.
- Do not commit secrets, generated Firebase config, signing files, or local
  machine config.
- Report skipped checks with the exact reason.
