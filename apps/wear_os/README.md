# Fall Guardian Wear OS App

Native Android Wear OS app for watch-side fall detection and alert handoff.

## Responsibilities

- run fall detection on Wear OS using watch sensors
- start the watch-side alert experience
- communicate fall events to the assisted user's phone
- keep watch contracts aligned with the assisted app and backend

## Requirements

- Android Studio
- JDK 17
- Android SDK with API 34
- Wear OS emulator or compatible watch

## Setup

```sh
./gradlew build
```

## Verification

```sh
./gradlew test
./gradlew build
```

Use Android Studio or `adb` for emulator/device install and runtime testing.

## Related Repositories

- `../assisted_mobile`: assisted user mobile app
- `../../backend/api`: backend API
- `../watchos`: watchOS counterpart
