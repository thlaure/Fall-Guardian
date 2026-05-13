# Agent Guide

This repository contains the Fall Guardian caregiver Flutter mobile app.

Also follow the workspace-level guide at `../AGENTS.md` when working from the parent folder.

`CLAUDE.md` must stay a thin pointer to this file.

## Project

- Flutter app for caregivers who receive alerts and manage assisted-user links
- Owns caregiver notification UX, invite/link flows, and caregiver-facing API interaction
- Keep widgets UI-only and keep workflow logic in focused services

## Engineering Rules

Always:

- keep caregiver API contracts aligned with `fall_guardian_api`
- keep generated Flutter/iOS/Android files out of Git unless they are intentionally source-controlled by Flutter
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
flutter analyze
flutter test
```
