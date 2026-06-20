# Fall Guardian

Fall Guardian is a multi-platform fall detection and alert system.

## Layout

```text
fall_guardian_monorepo/
├── apps/
│   ├── assisted_mobile/
│   ├── caregiver_mobile/
│   ├── wear_os/
│   └── watchos/
├── backend/
│   └── api/
├── packages/
├── docs/
└── scripts/
```

## Projects

- `backend/api`: Symfony/API Platform backend.
- `apps/assisted_mobile`: Flutter assisted person mobile app.
- `apps/caregiver_mobile`: Flutter caregiver mobile app.
- `apps/wear_os`: native Wear OS fall detection app.
- `apps/watchos`: native watchOS fall detection app.

Each project keeps its own build system and local instructions. The root
Makefile only orchestrates common checks across projects.

## Verification

Run all deterministic checks:

```sh
make quality
```

Run checks for a single project:

```sh
make quality-api
make quality-assisted
make quality-caregiver
make quality-wear-os
make quality-watchos
```

