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
heads-up alert whose **Open to cancel** action opens the alert screen; the
notification itself never cancels. Cancelling always needs a deliberate
**1.5-second press-and-hold** on **I'm OK** (a green fill shows progress, a
haptic tick confirms, releasing early aborts), matching watchOS. TalkBack users
get a "Hold to cancel" action that opens an explicit Yes/No confirmation. The
countdown is announced through a polite live region (every 10 s, then each of
the last 5 s); alert text follows the system font size up to 1.3x. Per-second
haptics are played by the foreground service, so they also work screen-off.

If the process dies during the 30-second window, the active incident
(incident id, wall fall timestamp, deadline, monotonic anchor, boot count) is
restored from private storage, the alert screen/notification come back, and
the fall is re-sent to the phone with the **same** `incidentId` and original
timestamp (the phone de-duplicates by id), in case the process died before
the Data Layer write. An expired or cancelled incident is never restored.

The countdown runs on `SystemClock.elapsedRealtime()` anchored at detection,
so a wall-clock change cannot end or extend it; after a reboot
(`Settings.Global.BOOT_COUNT` differs) it falls back to the wall clock. The
phone still receives the wall-clock timestamp.

All alert decisions (start, cancel, phone cancel, expiry, restore, Data Layer
ordering) live in the pure, unit-tested `AlertSession`; `WearDataSender` only
supplies clocks and executes its effects. The hold-to-cancel confirmation
buzz is played by the service after it stops the alarm vibration.

## Watch ↔ phone contract

Every confirmed fall gets an `incidentId` (lowercase random UUID). Paths and
legacy fields are unchanged so phone builds without incident ids keep working.

| Direction | Path | Transport | Payload |
| --- | --- | --- | --- |
| watch → phone | `/fall_event` | message | 8-byte big-endian fall `timestamp` (ms), then UTF-8 `incidentId` (36 bytes) |
| watch → phone | `/fall_event` | data item | `timestamp`, `updatedAt`, `incidentId` |
| watch → phone | `/cancel_alert` | message | JSON `{"event":"alert_cancelled","incidentId":…,"fallTimestamp":…}` |
| watch → phone | `/cancel_alert` | data item | `timestamp` (= fall time), `fallTimestamp`, `incidentId`, `cancelledAt`, `updatedAt` |
| phone → watch | `/cancel_alert` | message | optional JSON `incidentId` / `fallTimestamp` |

Incoming phone cancels: with an `incidentId`, ignored unless it matches the
active alert; with only `fallTimestamp`, must match the active fall; with
neither (legacy phone), accepted only while an alert is active.

Data items use one path each, so a newer incident overwrites an older one.
Cancelling deletes the queued `/fall_event` item (a cancelled fall is never
replayed after a long disconnect, and a cancel cannot be overtaken by its own
fall). A new fall deletes any undelivered `/cancel_alert` item, so an old
cancel can never close the new alert on an older phone build; worst case the
previous incident escalates, which is the safe direction.

## Sensor batching and battery

The service prefers the **wake-up** accelerometer
(`getDefaultSensor(TYPE_ACCELEROMETER, true)`) at 25 Hz with a
`maxReportLatency` of 5 s, capped to the FIFO space **reserved** for that
sensor (`fifoReservedEventCount`; `fifoMaxEventCount` is shared with other
sensors and not guaranteed). The sensor hub buffers samples in its FIFO while the CPU
sleeps and wakes it only to deliver a batch (≤ 0.2 wake-ups/s; fewer callbacks
than before while the screen is on). The previous non-wake-up sensor stopped
delivering, and dropped samples, once the CPU slept, so screen-off falls could
be missed. If no wake-up variant exists or its FIFO holds less than 2 s, the
previous non-wake-up 500 ms batching is used. The `sensor_registration`
diagnostic event logs `wake_up`, `fifo_reserved`, `fifo_max`, `period_us` and
`batch_us`. No monitoring wake lock is held;
a 35 s wake lock is taken only once a fall is confirmed. Trade-off: up to 5 s
extra alert latency and a small number of sleep wake-ups, measured on device
via diagnostics (`sensor_registration`, `sensor_elapsed_ms` vs
`delivery_elapsed_ms`). Sampling stays at 25 Hz: 50 Hz doubles FIFO fill and
thus wake-ups when the FIFO limits batching, unjustified without measurements.

Algorithm defaults are `0.35 g` low acceleration, `4.2 g` impact, `80°`
orientation change, and `160 ms` minimum low-acceleration duration. Detection
requires qualified low acceleration, impact, orientation change, and
post-impact stillness; all four conditions must be present.

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

## Detection diagnostics (Release and Debug)

The idle watch screen can enable/disable local diagnostic recording. It is off
by default. Recording does not change thresholds, sensor subscription, wake
locks, or alert delivery. It records **every delivered accelerometer sample**,
including rejected and sub-threshold events, so a missed fall does not need to
trigger the existing detector to be investigated. No GPS, credentials or phone
data are recorded or uploaded.

Storage is private, compressed and bounded to 64 MiB and at most 72 hours;
the byte cap can shorten the available history. Export promptly after a real
event. Completed batches survive restart; the latest in-memory batch (up to
100 samples) can be lost on abrupt process death. Disk/queue losses are exposed
in status. Heartbeats run every 30 seconds **when the CPU runs**, without a
monitoring wake lock. No samples/heartbeats during sleep is a diagnostic finding,
not proof of continuous monitoring.

ADB shell export works on a signed Release build; normal apps cannot access it:

```sh
adb -s <watch> shell content call --uri content://com.fallguardian.diagnostics --method enable
adb -s <watch> shell content query --uri content://com.fallguardian.diagnostics/status
adb -s <watch> exec-out content read --uri content://com.fallguardian.diagnostics/export > watch-diagnostics.zip
adb -s <watch> shell content call --uri content://com.fallguardian.diagnostics --method disable
```

The ZIP contains `status.txt`, `events-*.csv` and `samples-*.csv.gz` (concatenated
gzip members, readable with Python `gzip` or `gzip -dc`). Raw acceleration is in
m/s². `sensor_elapsed_ms` is monotonic measurement time; `delivery_elapsed_ms`
is callback time. Their difference reveals delayed delivery. `interactive`
is sampled at most once per second to limit diagnostic overhead and
indicates screen interactivity, **not** CPU sleep. Rows also contain effective
thresholds, impact/low-acceleration/orientation qualification, stillness duration,
candidate expiration, detector output, and whether the service dispatched it.
Sample gaps, dropped samples and service restarts must be considered before
classifying an event as an algorithmic false negative. Note the time and
circumstances of spontaneous falls; never ask a vulnerable wearer to fall.

## Quality Checks

Run the deterministic verification set:

```sh
make check
```

This runs:

- JVM tests (including trace replay).
- Kover line-coverage gate (`make coverage`, `koverVerifyDebug`). It covers the
  JVM-testable logic (detection, diagnostics storage, alert contract and
  persistence, alert UI/sensor policy) and must stay at or above 90 % (it
  measured 100 % when introduced). Activity/Compose
  UI, services, receivers, the content provider and the
  Handler/Data Layer/SharedPreferences singletons are excluded because they
  need a device; they delegate their decisions to the covered classes. The
  HTML/XML report is in `app/build/reports/kover/`.
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

## Battery validation before release

**Status: pending.** The wake-up sensor change has not been measured on a
physical watch yet; do not release it until this is done.

Compare a build with this change against the #129 baseline (non-wake-up
accelerometer, 500 ms batches, no monitoring wake lock) on the same watch:

1. Install the build, charge to 100 %, unplug, keep the phone paired, wear
   the watch for a normal day (or leave it still on a desk for a
   worst-case-idle run). Same scenario and duration for both builds.
2. Enable diagnostics (see "Detection diagnostics"). Record start/end battery
   with `adb -s <watch> shell dumpsys battery` and reset/collect
   `adb -s <watch> shell dumpsys batterystats --reset` /
   `adb -s <watch> shell dumpsys batterystats com.fallguardian` after 24 h.
3. Export the diagnostics ZIP and check:
   - `events-*.csv` `sensor_registration`: `wake_up=true` and the
     `fifo_reserved` / `batch_us` actually used;
   - `samples-*.csv.gz`: no multi-second `sensor_elapsed_ms` gaps while the
     screen is off (the #129 build shows them), and the
     `delivery_elapsed_ms` cadence (≈ one batch per `batch_us`);
   - heartbeat gaps (CPU sleep is expected and fine).
4. Acceptance: 24 h drain at most a few percentage points above the #129
   baseline, with continuous screen-off samples. Record the numbers here.

Diagnostics recording itself costs battery; compare runs with the same
diagnostics setting.

## Replay traces

`FallTraceReplayTest` replays every trace in `app/src/test/resources/traces/`
through the production `FallAlgorithm` (default thresholds, 5 s cooldown, as in
`FallDetectionService`) and checks the expected outcome.

Format: exactly the diagnostics export (`samples-*.csv.gz` from the ZIP, or the
same data as plain `.csv`). The header is `FallDiagnosticSample.HEADER`; only
`sensor_elapsed_ms` (monotonic ms, non-decreasing) and `ax_ms2`, `ay_ms2`,
`az_ms2` (m/s²) are required, other columns are ignored, so detector output in
the file never influences the replay.

Each trace must be listed in `traces/labels.csv` (`file,expect_fall,description`,
description optional and quoted if it contains commas); an unlabelled file
fails the test. To add a real recording: copy the exported segment (optionally
trimmed around the event) into the folder, add a label row with what actually
happened, and run `make test`. Do not add personal data to descriptions.

> **The checked-in `synthetic-*.csv` traces are model-generated regression
> fixtures, not real-world validation.** They (fall forward, fall sideways,
> sitting down hard, table bump, walking) are hand-shaped approximations that
> pin the detector's current behaviour so changes are noticed; they say nothing
> about sensitivity or false-positive rate on real wearers. Regenerate them
> with `python3 scripts/generate_synthetic_traces.py`. `labels.csv` allows `#`
> comment lines.

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
