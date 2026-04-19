Verify a Fall Guardian change using the repository's real quality gates.

Verification scope: `$ARGUMENTS`

Workflow:
1. Read the relevant `Makefile` files and `AGENTS.md`.
2. Identify the canonical commands exposed by the repo.
3. Prefer the project wrappers over raw vendor commands.
4. Run the narrowest relevant tests first, then the broader required checks.
5. Report failures with the command, impacted files, and minimal fix direction.

Typical order:
1. `make check`
2. `cd flutter_app && flutter analyze`
3. `cd flutter_app && flutter test`
4. `cd backend && vendor/bin/phpstan analyse --no-progress --memory-limit=-1`
5. `cd backend && vendor/bin/phpunit --testsuite=Unit`
6. Add native or integration verification when the changed layer requires it

For targeted runs only, prefer the narrowest relevant command in the affected layer:
- top-level `make test` / `make analyze`
- `cd flutter_app && flutter test <target>`
- `cd backend && vendor/bin/phpunit <target>`
- `cd backend && vendor/bin/phpstan analyse <path>`

Output format:
- `Commands run`
- `Pass/fail summary`
- `Remaining gaps`

Rules:
- If a command is unavailable, say so instead of inventing a substitute.
- If Docker is required, use the project commands or wrappers already defined.
- If a change affects endpoint behavior, do not stop at unit tests only.
- If a change affects Flutter/native/backend contracts, do not stop at one layer's checks only.
- When fixing PHPStan issues, prefer correcting the code, types, or annotations instead of changing `phpstan.neon`.
- Treat edits to `phpstan.neon` as exceptional and ask first unless the user explicitly requested a PHPStan configuration change.
