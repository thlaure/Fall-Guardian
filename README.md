# Fall Guardian

Fall Guardian is a cross-platform fall detection system built for people who need a faster, more reliable response than standard “immobility-based” fall alerts.

The watch detects the fall. The watch and phone start a synchronized 30-second alert. If the alert is not cancelled, the phone escalates to emergency contacts.

## Why this project exists

Many built-in fall detection systems wait for the person to remain motionless after a fall. That is a poor fit for conditions such as **Progressive Supranuclear Palsy (PSP)**, where falls can be abrupt, atypical, and not followed by long immobility.

Fall Guardian is designed to react to the **fall event itself**.

## What it does

- Runs fall detection continuously on the watch
- Starts a 30-second alert on the watch immediately after detection
- Turns the phone into an alert surface too
- Lets the alert be cancelled from either watch or phone
- Escalates to emergency contacts if the countdown expires
- Includes location in the message when available
- Keeps alert history and sensitivity settings on the phone

## Supported platforms

- iPhone + Apple Watch
- Android phone + Wear OS watch

Implementation split:
- phone app: Flutter
- Apple Watch app: native Swift/watchOS
- Wear OS app: native Kotlin

## How the system works

```text
Watch detects fall
        ↓
Watch starts 30-second countdown
        ↓
Phone receives shared fall timestamp
        ↓
Phone shows alert UI if foregrounded
or system notification if backgrounded
        ↓
Cancel from either device stops both sides
        ↓
If timeout expires, phone starts escalation
```

## Project architecture

```text
fall_guardian/
├── flutter_app/    # Shared phone app (iOS + Android)
├── wear_os_app/    # Native Wear OS app
└── watchos_app/    # Native watchOS app
```

Phone-side architecture is intentionally split into:
- workflow orchestration
- UI
- persistence adapters
- platform/service adapters

The alert workflow is centered on `AlertCoordinator`, which owns alert state transitions and keeps safety-critical behavior out of widget lifecycles.

For full architecture and invariants:
- [`PROJECT_CONTEXT.md`](/Users/thomaslaure/Documents/projects/fall_guardian/PROJECT_CONTEXT.md)
- [`WORKFLOW.md`](/Users/thomaslaure/Documents/projects/fall_guardian/WORKFLOW.md)

## Quick start

### Prerequisites

- Flutter `>= 3.43` on the beta channel
- Android Studio
- Xcode `>= 26`
- Android emulator and/or Wear OS emulator
- iPhone simulator and/or Apple Watch simulator

### Main commands

From the repo root:

```bash
make check
make run-ios
make run-android
make run-wear
```

Useful commands:

```bash
make test-e2e-ios
make test-e2e-android
make test-e2e-all
```

### Build phone targets directly

```bash
cd flutter_app
flutter build apk --debug
flutter build ios --simulator --debug -d <ios-sim-id>
```

## Development notes

### Android release signing

Release builds fail closed unless signing is configured.

Provide either:
- a local `keystore.properties` file at the repo root
- or these environment variables:
  - `ANDROID_KEYSTORE_PATH`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`

### iOS/watchOS

The iOS project uses the UIScene lifecycle required by modern iOS simulator targets. If the iOS project is ever missing, regenerate it with:

```bash
cd flutter_app
flutter create --platforms=ios --org com.fallguardian .
```

### Simulator caveat

Simulator communication between iPhone and Apple Watch is less reliable than real hardware. Treat simulator validation as useful, but not final, for safety-critical flows.

## Testing

Baseline verification:

```bash
make check
```

This runs:
- formatting
- Flutter unit and widget tests
- Flutter static analysis

The repo also includes end-to-end automation for:
- iOS + watchOS
- Android + Wear OS

## Current limitations

- iOS cannot perform silent SMS sending in the same way Android can
- Apple Watch/iPhone simulator communication is not equivalent to real-device behavior
- Some Flutter plugins still warn about missing Swift Package Manager support

For temporary status and current caveats:
- [`CURRENT_STATUS.md`](/Users/thomaslaure/Documents/projects/fall_guardian/CURRENT_STATUS.md)

## Documentation

- [`PROJECT_CONTEXT.md`](/Users/thomaslaure/Documents/projects/fall_guardian/PROJECT_CONTEXT.md): shared architecture and invariants
- [`WORKFLOW.md`](/Users/thomaslaure/Documents/projects/fall_guardian/WORKFLOW.md): detailed runtime behavior
- [`CURRENT_STATUS.md`](/Users/thomaslaure/Documents/projects/fall_guardian/CURRENT_STATUS.md): current limitations and temporary warnings

## Status

This project is architecturally solid and actively being hardened, but it should still be treated as a safety-critical system under validation rather than a finished consumer product.
