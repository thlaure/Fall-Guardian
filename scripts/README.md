# Workspace scripts

Automation shared across the monorepo. Project-specific tooling stays inside
its project (`backend/api`, `apps/*`).

| Script | Used by | Purpose |
| --- | --- | --- |
| `deploy-api-remote.sh` | `.github/workflows/api-deploy.yaml` | Runs on the production VPS over SSH: pull image, migrate with the new image, start containers, probe `/health`, roll containers back to the previous image on failure. |

Scripts must pass `shellcheck` (enforced in API CI) and must not embed secrets:
take paths and image references as arguments, read credentials from the host.
