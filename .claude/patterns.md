# Fall Guardian Patterns

Use these pointers before creating new patterns:

- Root workspace rules: `AGENTS.md`
- Backend architecture: `backend/api/AGENTS.md`
- Assisted Flutter app: `apps/assisted_mobile/AGENTS.md`
- Caregiver Flutter app: `apps/caregiver_mobile/AGENTS.md`
- Wear OS app: `apps/wear_os/AGENTS.md`
- watchOS app: `apps/watchos/AGENTS.md`

Shared principles:

- Put behavior in the owning project.
- Keep cross-project contracts explicit and tested.
- Keep safety-critical alert flows readable.
- Prefer deterministic quality tools before agent judgment.
- Add a local pattern only after the same shape appears more than once and
  reduces real complexity.
