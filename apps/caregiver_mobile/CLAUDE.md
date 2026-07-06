# Claude Guide

This repository contains the Fall Guardian caregiver Flutter mobile app.

Also follow the workspace-level guide at `../../CLAUDE.md` when working from
this project.

## Project

- Flutter app for caregivers who receive alerts and manage assisted-user links
- Owns caregiver notification UX, invite/link flows, and caregiver-facing API interaction
- Keep widgets UI-only and keep workflow logic in focused services

## Engineering Rules

Always:

- keep caregiver API contracts aligned with `../../backend/api`
- keep generated Flutter/iOS/Android files out of Git unless they are intentionally source-controlled by Flutter
- prefer readable, explicit code over clever Flutter/platform tricks
- add concise comments for mobile/platform concepts, async flows, native bridges, permissions, background execution, notification delivery, and safety-critical alert behavior when they are not obvious to a non-mobile developer
- keep automated line coverage at or above 90%; coverage must come from useful behavior, contract, edge-case, and regression tests, not shallow line execution
- enforce the 90% coverage gate on behavior code through `make quality`; UI rendering, localization text, and thin platform-plugin wrappers may be excluded from the threshold when their useful behavior is covered elsewhere
- run `flutter analyze` after Dart changes when feasible
- run `flutter test` for behavior changes when tests exist or are added

Ask first:

- adding Flutter packages or native plugins
- changing bundle IDs, Firebase config, signing, entitlements, notification capabilities, or deployment targets
- changing caregiver notification delivery or invite/link contracts

Never:

- hardcode API secrets, tokens, or production-only local values
- put notification or linking workflow logic directly in Flutter widgets

## Verification

Common commands:

```sh
make quality
make build-android
make build-ios
```
