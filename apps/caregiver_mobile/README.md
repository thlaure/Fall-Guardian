# Fall Guardian Caregiver App

Flutter mobile app for caregivers. It owns caregiver registration, assisted-user
linking, push notification registration, alert display, and caregiver-facing API
interaction.

## Responsibilities

- register caregiver devices with the backend
- handle Firebase push notification setup
- support caregiver invite/link flows
- display fall alerts and acknowledgement state
- keep caregiver contracts aligned with `fall_guardian_api`

## Requirements

- Flutter SDK compatible with the Dart SDK declared in `pubspec.yaml`
- Android Studio or Xcode for platform builds
- Firebase configuration for push notifications
- backend API available locally or remotely

## Setup

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

Without these values, Firebase initialization is skipped at runtime and push
notifications are unavailable for that build.

## Verification

```sh
flutter analyze
flutter test
```

Run platform builds from this repo when changing native Android, iOS, Firebase,
or notification configuration.

## Related Repositories

- `../fall_guardian_api`: backend API
- `../fall_guardian_assisted_app`: assisted user mobile app
- `../fall_guardian_wear_os_app`: Wear OS watch app
- `../fall_guardian_watchos_app`: watchOS app
