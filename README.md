# Fall Guardian

Fall Guardian is a multi-platform fall detection and alert system. It separates
fall detection, phone-side alert coordination, caregiver notification, and API
persistence into focused projects inside one monorepo.

## Product Flow

```text
watch detects possible fall
-> assisted mobile app starts a cancellable countdown
-> uncancelled alert is submitted to the backend API
-> backend stores the alert and notifies linked caregiver devices
-> caregiver app shows the active alert and history
-> caregiver can acknowledge the alert
```

Cancelled alerts are still part of the backend history so caregivers can see
that an assisted user stopped the escalation.

## Repository Layout

```text
fall_guardian_monorepo/
├── apps/
│   ├── assisted_mobile/     Flutter app for the assisted person
│   ├── caregiver_mobile/    Flutter app for caregivers
│   ├── wear_os/             native Wear OS watch app
│   └── watchos/             native Apple Watch app
├── backend/
│   └── api/                 Symfony/API Platform backend
├── packages/                reserved for shared contracts or generated assets
├── docs/                    workspace-level documentation
└── scripts/                 workspace automation
```

Each project keeps its own build system, README, and agent instructions. The
root Makefile only orchestrates common checks.

## Projects

- `backend/api`: device identity, invite linking, fall-alert persistence, push
  dispatch, alert history, acknowledgement, cancellation, rate limiting, and API
  documentation.
- `apps/assisted_mobile`: phone app used by the assisted person. It receives
  watch events, runs the countdown, manages contacts, submits alerts, and lets
  the user cancel an alert before escalation.
- `apps/caregiver_mobile`: phone app used by caregivers. It links to one or
  more assisted persons, registers for push notifications, displays active
  alerts, and shows alert history.
- `apps/wear_os`: native Android watch app for Wear OS sensor-based fall
  detection and handoff to the assisted Android phone.
- `apps/watchos`: native watchOS app for Apple Watch sensor-based fall detection
  and handoff to the assisted iPhone.

## Local Requirements

- Flutter SDK for the two mobile apps.
- Android Studio, Android SDK, and JDK 17 for Android/Wear OS builds.
- Xcode for iOS/watchOS builds.
- Docker Compose or Podman Compose for the backend.
- GitHub CLI if you need to create or inspect pull requests locally.

The backend Makefile chooses `podman compose` when Podman is installed, and
falls back to `docker compose` otherwise.

## Common Commands

Show available root commands:

```sh
make help
```

Run all deterministic checks:

```sh
make quality
```

Run checks for one project:

```sh
make quality-api
make quality-assisted
make quality-caregiver
make quality-wear-os
make quality-watchos
```

Check repository state:

```sh
make status
```

## Development Workflow

1. Start from `main` and pull the latest changes.
2. Create a short-lived branch for the change.
3. Keep changes in the project that owns the behavior.
4. For cross-project contract changes, update the backend and affected apps in
   the same branch so the feature remains testable end to end.
5. Run the project-level quality command before pushing.
6. Open a PR and wait for CI to pass before merging.

## Quality And Security Rules

- Keep automated line coverage at or above 90% when practical.
- Prefer useful tests that verify behavior, contracts, edge cases, and
  regressions over tests that only execute lines.
- Do not commit secrets, tokens, certificates, signing files, generated native
  Firebase files, or local machine configuration.
- Use deterministic tools first: formatters, linters, static analysis, tests,
  builds, dependency scanners, security scanners, and compiler checks.
- Use agent hooks for fast local safety checks.
- Use written guidance and skills for judgment-heavy architecture and review.

## API And Device Integration

Default local backend documentation is available at:

```text
http://localhost:8002/docs
```

Default local API base path:

```text
http://localhost:8002/api/v1
```

When testing on a wired Android device, the mobile Makefiles can reverse
`localhost:8002` through ADB with their `run-android-wired` targets.

## More Documentation

Read the project README closest to the code you are changing:

- `backend/api/README.md`
- `apps/assisted_mobile/README.md`
- `apps/caregiver_mobile/README.md`
- `apps/wear_os/README.md`
- `apps/watchos/README.md`
