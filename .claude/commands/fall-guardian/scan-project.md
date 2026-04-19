Review this Fall Guardian repository and produce an implementation-ready map.

User request: `$ARGUMENTS`

Workflow:
1. Read `AGENTS.md`, `CLAUDE.md`, `README.md`, `composer.json`, and `Makefile`.
2. Inspect the project layout before proposing any change:
   - `flutter_app/`
   - `caregiver_app/`
   - `wear_os_app/`
   - `watchos_app/`
   - `backend/`
   - `.claude/`
3. Detect the active conventions:
   - Flutter and Dart app structure
   - native Android/Wear OS and iOS/watchOS bridge patterns
   - Symfony/API Platform backend usage style
   - Docker/FrankenPHP setup where relevant
   - coordinator-owned, native-bridge, and service-driven workflow ownership
   - test stack and quality gates
4. Identify the nearest existing pattern for the requested area.
5. Call out project-specific constraints that matter before coding.

Output format:
- `Context`: 4-8 bullets with relevant architecture and tooling facts
- `Existing patterns`: file paths worth mirroring
- `Files likely to change`: exact paths or tight glob patterns
- `Risks`: regressions, hidden coupling, or prerequisites
- `Implementation plan`: short numbered list

Rules:
- Prefer local project patterns over Symfony defaults.
- Do not invent new folders or layers when the repo already has a clear shape.
- When the request crosses Flutter, native, and backend boundaries, explicitly call out the shared contract points.
- Surface any policy in `AGENTS.md` that requires explicit confirmation before changes.
