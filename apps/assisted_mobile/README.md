# Fall Guardian Assisted App

Flutter mobile app used by the assisted person. It owns the phone-side alert
experience: receiving watch fall events, running the countdown, cancelling or
submitting alerts, managing emergency contacts, and syncing with the backend.

## Responsibilities

- Receive fall events from supported watches.
- Start a clear, cancellable local fall-alert countdown.
- Submit uncancelled fall alerts to the backend.
- Record cancelled alerts through the backend so caregivers can see history.
- Manage emergency contacts.
- Send local notifications and SMS fallback where supported.
- Keep backend, caregiver, Wear OS, and watchOS contracts aligned.

## User Flow

```text
watch reports fall event
-> assisted app opens alert countdown
-> assisted user can cancel before escalation
-> if not cancelled, app sends alert to backend
-> backend notifies linked caregivers
```

The assisted app is the coordinator. Watches detect; the phone decides whether
the alert is cancelled or escalated.

## Code Layout

```text
lib/
├── main.dart
├── l10n/                         generated/localized strings
├── models/
│   ├── contact.dart
│   └── fall_event.dart
├── repositories/
│   ├── contacts_repository.dart
│   ├── fall_events_repository.dart
│   └── shared_preferences_migration.dart
├── screens/
│   ├── contacts_screen.dart
│   ├── fall_alert_screen.dart
│   ├── history_screen.dart
│   ├── home_screen.dart
│   └── settings_screen.dart
└── services/
    ├── alert_coordinator.dart
    ├── alert_ports.dart
    ├── alert_runtime.dart
    ├── app_bootstrap_service.dart
    ├── backend_api_service.dart
    ├── location_service.dart
    ├── notification_service.dart
    ├── secure_store.dart
    ├── sms_service.dart
    └── watch_communication_service.dart
```

Important services:

- `AlertCoordinator`: orchestrates detection, countdown, cancellation, and
  escalation.
- `BackendApiService`: talks to the Symfony backend.
- `WatchCommunicationService`: receives watch-side fall events.
- `NotificationService`: owns local mobile notifications.
- `SmsService`: sends configured emergency SMS messages when available.
- `SecureStore`: stores sensitive local values.

## Requirements

- Flutter SDK compatible with Dart `>=3.0.0 <4.0.0`.
- Android Studio or Xcode for platform builds.
- Android device/emulator or iPhone/simulator.
- Backend API available locally or remotely.

## Setup

Install dependencies:

```sh
make install
```

Equivalent direct command:

```sh
flutter pub get
```

## Backend Configuration

The app reads the backend URL from `BACKEND_BASE_URL` when provided:

```sh
make run-ios-profile BACKEND_BASE_URL=http://192.168.1.10:8002
make run-android-debug BACKEND_BASE_URL=http://192.168.1.10:8002
```

For a wired Android device connected to a backend running on the development
machine:

```sh
make run-android-wired
```

That target configures ADB reverse proxying for `localhost:8002`.

## Run And Build

Build Android debug APK:

```sh
make build-android
```

Build iOS simulator app:

```sh
make build-ios
```

Run Android debug:

```sh
make run-android-debug DEVICE_ID=<device-id>
```

Run iOS profile:

```sh
make run-ios-profile DEVICE_ID=<device-id>
```

## Logs

Flutter logs:

```sh
make logs-flutter DEVICE_ID=<device-id>
```

Android process logs:

```sh
make logs-android DEVICE_ID=<device-id>
```

iOS console logs:

```sh
make logs-ios-console IOS_DEVICE_ID=<device-id>
```

## Quality Checks

Run the deterministic verification set:

```sh
make quality
```

This runs:

- Dart format check.
- Flutter static analysis.
- Flutter tests with coverage.
- Coverage threshold check.

Individual commands:

```sh
make format-check
make analyze
make test
make coverage-check
```

## Testing Guidance

Prioritize tests around:

- fall countdown start/cancel/escalate behavior;
- backend request payloads and timeout/error handling;
- local storage migrations;
- contact validation;
- watch communication boundaries;
- notification and SMS failure paths.

Keep coverage at or above 90% where practical, but do not add tests that only
execute lines without proving behavior.

## Safety And UX Notes

- The user must always understand whether an alert is pending, cancelled, or
  escalated.
- Cancellation must be explicit and must not silently drop history.
- Network failures should produce actionable UI and logs.
- Prefer readable Dart over clever abstractions; this project is maintained by
  developers who may not specialize in mobile.
- Add concise comments for platform, permission, async, and safety-critical
  behavior when the code is not obvious.

## Related Projects

- `../../backend/api`: backend API.
- `../caregiver_mobile`: caregiver mobile app.
- `../wear_os`: Wear OS watch app.
- `../watchos`: watchOS app.
