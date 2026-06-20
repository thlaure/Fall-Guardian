@/Users/thomaslaure/.codex/RTK.md

# Fall Guardian Monorepo Guide

Use Caveman mode by default, full intensity, unless the user asks otherwise.
Use RTK for shell commands when compatible with tool constraints.

## Layout

```text
apps/assisted_mobile/     Flutter assisted person app
apps/caregiver_mobile/    Flutter caregiver app
apps/wear_os/             native Wear OS app
apps/watchos/             native watchOS app
backend/api/              Symfony/API Platform backend
packages/                 shared contracts, fixtures, and generated artifacts
docs/                     workspace documentation
scripts/                  workspace automation
```

## Rules

- Keep platform apps modular; this is a monorepo, not a monolith.
- Preserve API/mobile/watch contracts when changing alert, invite, device, push,
  acknowledgement, cancellation, or history behavior.
- Prefer one PR for cross-project contract changes so API and apps stay in sync.
- Keep secrets, tokens, certificates, signing files, generated local config, and
  machine-specific files out of Git.
- Keep automated line coverage at or above 90% when practical.
- Tests must prove behavior, contracts, edge cases, and regressions.
- Check status before committing. Do not revert user changes.

## Claude / Codex Configuration

Shared Claude/Codex practices live at the monorepo root:

- `CLAUDE.md`: thin Claude entrypoint that points to this file and shared
  `.claude` guidance.
- `.claude/settings.json`: shared permissions and hooks.
- `.claude/hooks/`: deterministic safety checks around agent actions.
- `.claude/rules/`: shared architecture, security, and testing rules.
- `.claude/skills/`: shared task workflows such as review, security review,
  bug fix, feature work, and prepare-commit.
- `.claude/agents/`: shared QA and security reviewer agent definitions.

Project-local `CLAUDE.md` files must stay thin pointers to the local
`AGENTS.md`. Add a project-local `.claude/` only when a project needs genuinely
specific hooks, permissions, agents, or skills that do not belong to every
project.

## Guardrail Priority

Apply guardrails in this order:

1. Deterministic tools: formatters, linters, static analysis, tests, builds,
   dependency scanners, security scanners, compiler checks.
2. Agent hooks: fast local checks around actions, such as credential guards,
   protected branch guards, syntax checks, and write-scope checks.
3. Skills and written guidance: architecture, review, product, security, and
   judgment-heavy conventions.

Move repeatable rules into deterministic tools first. Use hooks only when a rule
must run immediately around an action. Use skills for work that requires context.

## Commit And PR Practice

- Work on a dedicated branch for commits and pushes; do not commit directly on
  `main`, `master`, or `develop`.
- Use one logical change per commit.
- Stage only intended files after inspecting `git status` and `git diff`.
- Prefer Conventional Commits:
  `{type}({scope}): {description}`.
- Useful scopes: `api`, `assisted`, `caregiver`, `wear-os`, `watchos`,
  `monorepo`, or backend domain names such as `alert`, `device`, `push`.
- Run relevant deterministic checks before commit.
- Mention skipped checks and the reason in the final response or PR body.
- Never commit secrets, generated Firebase files, signing material, local env
  files, or machine-specific configuration.

## Verification

Root commands:

```sh
make quality
make test
make status
```

Project commands:

- API: `make -C backend/api quality`, `make -C backend/api test`,
  `make -C backend/api test-behat`
- Assisted mobile: `make -C apps/assisted_mobile quality`
- Caregiver mobile: `make -C apps/caregiver_mobile quality`
- Wear OS: `make -C apps/wear_os check`
- watchOS: `make -C apps/watchos check`

If a check is skipped, report why.
