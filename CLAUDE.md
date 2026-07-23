# Claude Guide

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
- Never hand off a Flutter debug build on a physical iOS device: it cannot be
  relaunched from the home screen. Use profile (development) or release
  (production). Debug is allowed only while tooling remains attached, and must
  be replaced by a profile/release build before declaring deployment complete.

## Configuration Layout

This project's Claude config is self-contained — no Codex/AGENTS.md coupling.
If Codex support is ever needed again, symlink `AGENTS.md -> CLAUDE.md` per
project rather than maintaining duplicate content.

- `CLAUDE.md` (this file and each project-local one): canonical instructions.
- `.claude/settings.json`: shared permissions and hooks; versioned repo-default.
- `.claude/hooks/`: deterministic safety checks around agent actions.
- `.claude/rules/`: shared architecture, security, and testing rules.
- `.claude/patterns.md`: shared code-shape patterns.
- `.claude/agents/`: shared QA and security reviewer agent definitions.
- `.claude/skills/`: shared task workflows, matched to the task at hand:
  - new functionality: `.claude/skills/new-feature/SKILL.md`
  - bug fixing: `.claude/skills/bug-fix/SKILL.md`
  - review: `.claude/skills/review-change/SKILL.md`
  - security review: `.claude/skills/security-review/SKILL.md`
  - commit preparation: `.claude/skills/prepare-commit/SKILL.md`
  - quality/debugging failures: `.claude/skills/debug-quality/SKILL.md`
  - proactive quality verification (before declaring work done):
    `.claude/skills/verify-quality/SKILL.md`
  - PR review-comment/CI follow-up: `.claude/skills/review-pr-feedback/SKILL.md`
  - execution discipline for review, refactor, or ambiguity-heavy tasks:
    `.claude/skills/karpathy-guidelines/SKILL.md`
  - acceptance-criteria verification: `.claude/agents/qa-reviewer.md`
  - independent security review: `.claude/agents/security-reviewer.md`

Each project-local `CLAUDE.md` is canonical for that project and applies on
top of this file — do not repeat this list there. Add a project-local
`.claude/` only when a project needs genuinely specific hooks, permissions,
agents, or skills that do not belong to every project.

Prefer skills when the user is speaking naturally or explicitly invokes a
named workflow. Open the matching shared file on demand; do not preload the
full `.claude` tree. Keep rules, patterns, and skills consistent with each
other — propose fixes through the Instruction-File Policy below when they
drift.

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

## Instruction-File Policy

Living docs. Change only on durable evidence of drift (repeated corrections,
Makefile/composer/structure changes, conventions that changed in practice,
duplication). Propose first, apply only after explicit confirmation. No
one-off/local context.

Files in scope: every `CLAUDE.md` (root and project-local), `.claude/rules/*.md`,
`.claude/patterns.md`, `.claude/skills/*/SKILL.md`, `.claude/agents/*.md`,
`.claude/hooks/*.py`.

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
