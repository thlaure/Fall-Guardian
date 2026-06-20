# Fall Guardian Wear OS App

Native Android Wear OS app for watch-side fall detection and alert handoff to
the assisted Android phone.

## Responsibilities

- Read watch sensor data.
- Detect possible falls with native low-latency logic.
- Show watch-side detection/alert state.
- Send fall events to the assisted mobile app.
- Keep detection thresholds and event contracts aligned with the assisted app.

## Runtime Flow

```text
Wear OS sensors emit motion data
-> native detector evaluates fall threshold
-> watch app marks a possible fall
-> watch sends event to assisted Android phone
-> assisted app owns countdown and escalation
```

The watch does not notify caregivers directly. It only reports possible falls to
the assisted phone.

## Project Layout

```text
apps/wear_os/
├── app/
│   ├── build.gradle
│   └── src/
├── build.gradle
├── gradle.properties
├── settings.gradle
└── Makefile
```

The app uses the standard Android Gradle project layout. Keep watch-specific
code inside the Wear OS module rather than sharing mobile Flutter code.

## Requirements

- Android Studio.
- JDK 17.
- Android SDK with API 34.
- Wear OS emulator or compatible Wear OS watch.
- A paired Android phone or emulator when validating phone handoff.

## Setup

Build all Gradle targets:

```sh
make build
```

Equivalent direct command:

```sh
./gradlew build
```

## Run And Install

Build the debug APK:

```sh
make assemble-debug
```

Install it on the detected Wear OS emulator:

```sh
make install-debug
```

Override the target device when needed:

```sh
make install-debug WEAR_DEVICE=<adb-device-id>
```

List devices:

```sh
adb devices -l
```

## Quality Checks

Run the deterministic verification set:

```sh
make check
```

This runs:

- JVM tests.
- Android lint.
- Gradle build.

Individual commands:

```sh
make test
make lint
make build
```

## Testing Guidance

Prioritize tests around:

- fall algorithm threshold behavior;
- false-positive guardrails;
- event payload shape sent to the assisted app;
- lifecycle behavior when the watch app is backgrounded;
- debug automation paths not being exposed in production.

## Sensor And Safety Notes

- Keep detection code readable and explicitly named; threshold logic is
  safety-critical.
- Any user-facing threshold setting must affect the real detection rule.
- Avoid battery-heavy polling unless it is required for reliable detection.
- Do not send caregiver notifications directly from the watch.

## Related Projects

- `../assisted_mobile`: assisted user mobile app.
- `../../backend/api`: backend API.
- `../watchos`: watchOS counterpart.
