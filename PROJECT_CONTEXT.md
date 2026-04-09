# Fall Guardian — Shared Project Context

This file is the shared source of truth for AI coding agents working in this repository.

## Truth hierarchy

1. `PROJECT_CONTEXT.md` for architecture, invariants, and working rules
2. `WORKFLOW.md` for runtime behavior and expected product flow
3. Code for implementation truth
4. `AGENTS.md` and `CLAUDE.md` for agent-specific behavior only

If two documents disagree, prefer the one higher in this list. If docs disagree with code, inspect the code and update the docs.

## Product summary

Fall detection app for elderly and at-risk users.

Flow:
- watch detects a fall
- watch starts a 30-second alert
- phone becomes an alert surface
- if not cancelled within 30 seconds, emergency escalation starts

## Product requirements

1. Platforms: iOS + watchOS and Android + Wear OS. Feature behavior must stay aligned across all 4 platforms.
2. Fall detection runs on the watch, not the phone.
3. Alert flow:
   - watch detects fall and emits one shared timestamp
   - watch shows countdown immediately
   - phone shows full-screen alert if foregrounded
   - phone shows system notification when backgrounded or locked
   - either device can cancel
4. Sensitivity settings are edited on the phone and synced to the watch, with offline retry if needed.
5. Emergency contacts are managed on the phone.
6. Timeout escalation attempts to notify all configured contacts with location if available.

## Current architecture

Repository layout:

```text
fall_guardian/
├── flutter_app/
├── wear_os_app/
└── watchos_app/
```

### Phone app

The phone app is Flutter and currently uses a cleaner ports/adapters structure around the alert workflow:

- `models/`: pure data structures
- `repositories/`: persistence adapters
- `services/alert_ports.dart`: workflow-facing interfaces
- `services/alert_runtime.dart`: runtime adapters such as clock, locale, watch gateway
- `services/alert_coordinator.dart`: alert workflow/state machine
- `screens/`: UI only

Important design rule:
- keep alert workflow logic in `AlertCoordinator`
- keep UI in widgets
- keep storage/plugin/platform code behind ports or service adapters

### Native watch and phone bridges

Android/Wear OS:
- watch app is native Kotlin
- phone bridge uses `WearDataListenerService`
- Flutter/native channel name is `fall_guardian/watch`

iOS/watchOS:
- watch app is native Swift
- phone bridge uses `WatchSessionManager`
- Flutter/native channel name is `fall_guardian/watch`

## Cross-platform invariants

- Threshold keys must stay identical everywhere:
  - `thresh_freefall`
  - `thresh_impact`
  - `thresh_tilt`
  - `thresh_freefall_ms`
- MethodChannel name: `fall_guardian/watch`
- Native to Flutter methods:
  - `onFallDetected`
  - `onAlertCancelled`
- Flutter to native methods:
  - `sendThresholds`
  - `sendCancelAlert`
- Cancels received from the other device must not be echoed back.
- Countdown synchronization must use the shared fall timestamp, not local receive time.

## Security and persistence

- Phone-side sensitive data is stored through the secure storage bridge, not plain `SharedPreferences` for primary persistence.
- Android release builds must not use the debug signing config.
- Do not introduce new secrets or signing material into git.

## Current platform limitations

- Backend-owned SMS escalation is now the preferred path for the phone app; local device SMS should not be treated as the main production mechanism anymore.
- Simulator watch/phone communication is not as trustworthy as real-device behavior.
- `flutter_sms` and `flutter_local_notifications` still warn about missing Swift Package Manager support.

## Build and verification

Required baseline checks:

```bash
make check
cd flutter_app && flutter build apk --debug
cd flutter_app && flutter build ios --simulator --debug -d <ios-sim-id>
```

If changing native watch/phone integration, also verify the relevant native target.

## Git and PR workflow

- Use Conventional Commits for all commits.
- Prefer small, logically grouped commits over one large dump commit.
- Every PR must include:
  - a short summary of what changed
  - the main architectural or product impact
  - a checklist of what still needs to be manually checked
  - explicit mention of any known platform limitations that remain
- If behavior changed, update the docs in the same branch before opening the PR.

## Change impact checklists

### Alert flow changes

When changing alert flow, review:
- Flutter `AlertCoordinator`
- Flutter alert UI
- Android phone native bridge
- iOS phone native bridge
- Wear OS watch behavior
- watchOS behavior
- tests
- `WORKFLOW.md`

### Threshold sync changes

When changing threshold sync, review:
- Flutter payload keys
- Android phone sender
- Wear OS receiver and stored keys
- iOS phone sender
- watchOS receiver and stored keys

### Persistence changes

When changing persistence, review:
- migration behavior
- secure storage behavior
- repository tests
- any user-visible settings/history/contact flows

## Coding expectations

- Prefer architecture-preserving changes over local hacks.
- Keep dependency direction clean: workflow depends on ports, adapters depend on concrete platform details.
- Comment code where the next engineer would otherwise have to reverse-engineer intent.
- Avoid comments that restate obvious syntax.
- When behavior is safety-critical, add or update tests in the same change.

## Read next

- Read `WORKFLOW.md` for runtime behavior.
- Read `CURRENT_STATUS.md` for temporary limitations and active warnings.
