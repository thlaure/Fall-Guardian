# Fall Guardian watchOS App

Native watchOS app for Apple Watch fall detection and alert handoff to the
assisted iPhone.

## Responsibilities

- Read Apple Watch motion data.
- Detect possible falls with native watchOS logic.
- Show watch-side detection/alert state.
- Send fall events to the assisted iPhone.
- Keep detection thresholds and event contracts aligned with the assisted app.

## Runtime Flow

```text
Apple Watch sensors emit motion data
-> native detector evaluates impact + loss-of-balance + stillness phases
-> watch app marks a possible fall
-> watchOS presents a time-sensitive notification with sound and cancel action
-> watch sends event to assisted iPhone
-> assisted app owns countdown and escalation
```

The watch app does not call the backend and does not notify caregivers directly.
watchOS does not allow a third-party app to force itself into the foreground.
The supported background surface is therefore a time-sensitive local
notification that wakes the display, plays the default notification sound, and
offers **I'm OK — Cancel Alert**. Tapping the notification launches the app and
restores the original synchronized countdown. The action is ignored once the
30-second cancellation deadline has expired.

The standard sound respects the person's notification and Focus settings.
Bypassing silent mode or Focus would require Apple's separately approved
Critical Alerts entitlement.

Raw algorithm defaults are `0.7 g` low acceleration, `2.5 g` impact,
`50°` orientation change, and `60 ms` minimum low-acceleration duration.
An impact alone never triggers: the detector also requires orientation change
or qualified low acceleration, followed by about two seconds of stillness.

Foreground cancellation requires a deliberate 1.5-second hold. In Debug,
the raw detector stays active while the app is visible even when Apple's
system detector is authorized. Raw accelerometer streaming stops when watchOS
suspends the app; Release background behavior comes from
`CMFallDetectionManager`, not the raw algorithm.

The next increment is to consume the one-time enrollment sent by the iPhone,
claim watch-specific credentials, and store them in Keychain. See
`../../docs/COMPANION_ENROLLMENT.md`.

## Project Layout

```text
apps/watchos/
├── FallGuardian/
│   ├── FallGuardian.xcodeproj
│   └── FallGuardian Watch App/
├── FallGuardian WatchKit Extension/
├── FallGuardianTests/
└── Makefile
```

Core source files include:

- `ContentView.swift`: watch UI.
- `FallAlgorithm.swift`: fall detection rule.
- `FallDetectionManager.swift`: sensor lifecycle and detection coordination.
- `WatchSessionManager.swift`: communication with the iPhone.
- `FallGuardianTests/FallAlgorithmExecutableTests.swift`: deterministic
  algorithm tests run by `make test`.

## Requirements

- Xcode.
- watchOS simulator or compatible Apple Watch.
- iPhone companion/runtime context when validating phone communication.
- Apple approval for the Fall Detection capability on
  `com.fallguardian.app.watchkitapp` before physical system-fall validation.

## Setup

Open the project in Xcode:

```text
FallGuardian/FallGuardian.xcodeproj
```

The Makefile default destination is:

```text
platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)
```

Override it if your installed simulator has another name:

```sh
make build DESTINATION='platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)'
```

## Build And Test

Run deterministic checks:

```sh
make check
```

Individual commands:

```sh
make analyze
make build
make test
```

## Testing Guidance

Prioritize tests around:

- fall algorithm threshold behavior;
- normal motion that must not trigger a fall;
- edge cases around sensor spikes;
- watch-to-phone message payloads;
- lifecycle behavior when the watch app is paused or resumed.
- notification action cancellation while the interface is closed;
- countdown restoration after opening a fall notification.

## Sensor And Safety Notes

- Keep threshold logic explicit and easy to review.
- Any UI threshold setting must affect the real detection rule.
- Avoid battery-heavy sampling unless required for reliable detection.
- The assisted iPhone owns countdown, cancellation, backend submission, and
  caregiver notification.
- Apple approved the Fall Detection capability and signed builds embed the
  entitlement. Simulator algorithm tests still do not replace locked-iPhone
  and physical-watch validation.

## Related Projects

- `../assisted_mobile`: assisted user mobile app.
- `../wear_os`: Wear OS counterpart.
- `../../backend/api`: backend API.
