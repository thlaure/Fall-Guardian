# Fall Guardian Caregiver App

Flutter mobile app used by caregivers. It owns caregiver registration, linking
to assisted persons, push notification registration, active alert display, alert
history, and acknowledgement.

## Responsibilities

- Register caregiver devices with the backend.
- Link to one or more assisted persons through invite codes.
- Register Firebase push tokens.
- Receive and persist pending fall-alert push payloads.
- Display active alerts without duplicate overlapping dialogs.
- Show protected persons and alert history.
- Acknowledge fall alerts.
- Keep backend and assisted-app contracts aligned.

## User Flow

```text
caregiver opens app
-> app registers caregiver device
-> caregiver opens protected persons
-> caregiver enters assisted invite code
-> backend links caregiver to assisted person
-> caregiver receives push when an alert escalates
-> caregiver opens active alert and can acknowledge it
```

Cancelled assisted-side alerts appear in history with cancellation status.

## Code Layout

```text
lib/
├── firebase_options.dart
├── main.dart
├── l10n/                         generated/localized strings
├── screens/
│   ├── active_alert_screen.dart
│   ├── alert_history_screen.dart
│   ├── home_screen.dart
│   ├── link_screen.dart
│   └── protected_persons_screen.dart
└── services/
    ├── active_alert_presentation_state.dart
    ├── caregiver_backend_service.dart
    ├── pending_alert_store.dart
    └── push_notification_service.dart
```

Important services:

- `CaregiverBackendService`: backend device registration, linking, alert list,
  alert detail, push-token registration, and acknowledgement.
- `PushNotificationService`: Firebase Messaging setup and push handling.
- `PendingAlertStore`: durable pending-alert storage used when a push arrives
  before the UI can display it.
- `ActiveAlertPresentationState`: prevents repeated presentation of the same
  active alert.

## Requirements

- Flutter SDK compatible with the Dart SDK declared in `pubspec.yaml`.
- Android Studio or Xcode for platform builds.
- Firebase project configured for push notifications.
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

## Firebase Push Configuration

Do not commit generated Firebase native config files or API keys. The caregiver
app reads Firebase API keys from Dart defines:

```sh
make run-android-debug FIREBASE_ANDROID_API_KEY=...
make run-ios-profile FIREBASE_IOS_API_KEY=...
```

For local development, you can also create an ignored `.env.local` file:

```sh
FIREBASE_ANDROID_API_KEY=...
FIREBASE_IOS_API_KEY=...
```

The Makefile loads this file automatically and hides the Flutter command line so
API keys are not echoed in build logs.

For local Android over USB with backend reverse proxy:

```sh
make run-android-wired FIREBASE_ANDROID_API_KEY=...
```

Without these values, Firebase initialization is skipped at runtime and push
notifications are unavailable for that build.

iOS push notifications also require Apple-side configuration. Before adding an
`aps-environment` entitlement to the Xcode project, enable the Push
Notifications capability for `com.fallguardian.caregiverApp` in Apple
Developer/Xcode and regenerate the provisioning profile. Otherwise local device
builds fail with a provisioning profile error.

Ignored local/generated files:

```text
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

## Backend Configuration

The app reads the backend URL from `BACKEND_BASE_URL` when provided:

```sh
make run-ios-profile BACKEND_BASE_URL=http://192.168.1.10:8002 FIREBASE_IOS_API_KEY=...
make run-android-debug BACKEND_BASE_URL=http://192.168.1.10:8002 FIREBASE_ANDROID_API_KEY=...
```

For wired Android to a local backend:

```sh
make run-android-wired FIREBASE_ANDROID_API_KEY=...
```

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

- invite-code validation and linking;
- multiple protected persons;
- push payload parsing;
- duplicate active-alert prevention;
- pending alert persistence and migration;
- backend timeout and connection error handling;
- alert acknowledgement and history rendering.

Keep coverage at or above 90% where practical, but favor behavior-focused tests.

## Security Notes

- Do not commit Firebase API keys or native Firebase config files.
- Treat push payloads as untrusted input.
- Store pending alert data in secure storage when sensitive.
- Do not log device tokens, push tokens, invite codes, or exact user locations.

## UX Notes

- The home screen should make linked protected persons visible.
- Adding a protected person belongs inside the protected-persons view.
- Active alerts should be prominent but must not stack repeated dialogs.
- Network errors should explain that backend connectivity should be checked.
- Prefer readable Dart and concise comments for mobile/platform concepts.

## Related Projects

- `../../backend/api`: backend API.
- `../assisted_mobile`: assisted user mobile app.
- `../wear_os`: Wear OS watch app.
- `../watchos`: watchOS app.
