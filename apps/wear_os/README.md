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
-> native detector evaluates impact + loss-of-balance + stillness phases
-> watch app marks a possible fall
-> watch wakes an urgent countdown surface and starts alarm sound
-> watch sends event to assisted Android phone
-> assisted app owns countdown and escalation
```

The watch does not notify caregivers directly. It reports possible falls to
the assisted phone. The phone persists the incident before opening Flutter and
uses a native `JobService` to register or cancel it after process death or
temporary network loss. During the 30-second cancellation window, the watch plays a
looping alarm and posts a full-screen-intent notification. If Android does not
grant full-screen access, the same notification remains as a persistent
heads-up alert with an **I'm OK — Cancel** action. Foreground cancellation
requires a deliberate 1.5-second hold.

Algorithm defaults are `0.7 g` low acceleration, `2.5 g` impact, `50°`
orientation change, and `60 ms` minimum low-acceleration duration. An impact
alone is rejected; the detector also requires orientation change or qualified
low acceleration, followed by about two seconds of stillness.

Android 13 and newer require notification permission. Android 14 and newer can
also require the user to allow full-screen alerts in special app access. Sound
and the notification stop for watch cancellation, phone cancellation, or
countdown expiry. The idle screen exposes the missing access and opens the
relevant system setting when tapped.

The next Wear OS increment is to consume the one-time enrollment from the
phone, claim watch-specific credentials, and store them with Android Keystore.
See `../../docs/COMPANION_ENROLLMENT.md`.

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

Release builds for phone and watch must use the same signing key because the
Wear Data Layer verifies package identity. Configure `keystore.properties` or
the four `ANDROID_KEYSTORE_*` environment variables before
`./gradlew assembleRelease`; the build fails explicitly when they are absent.

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
- urgent notification, sound, and cancellation lifecycle;
- full-screen-intent denial falling back to an actionable notification;
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
