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
Apple system detects a serious fall while the app is foregrounded or suspended
-> CMFallDetectionManager wakes the Watch extension
-> Watch shows Fall Guardian's cancel action and sends one idempotent event to iPhone
-> iPhone native relay creates the API alert immediately
-> API owns the 30-second cancellation window and caregiver escalation
```

The watch app does not hold backend credentials and does not notify caregivers
directly. It uses WatchConnectivity to reach the paired iPhone, whose native
relay uses the protected person's Keychain-backed device credential. This means
the API grace period starts even when the Flutter engine has not been launched.
watchOS does not allow a third-party app to force itself into the foreground.
The supported background surface is therefore a time-sensitive local
notification that wakes the display, plays the default notification sound, and
offers **I'm OK — Cancel Alert**. Tapping the notification launches the app and
restores the original synchronized countdown. The action is ignored once the
30-second cancellation deadline has expired.

The standard sound respects the person's notification and Focus settings.
Bypassing silent mode or Focus would require Apple's separately approved
Critical Alerts entitlement.

Apple's `CMFallDetectionManager` is the supported background trigger. It needs
Apple's Fall Detection entitlement and the wearer's permission. Apple owns its
own emergency/SOS flow; Fall Guardian only starts its separate caregiver grace
window after receiving the system event. A rejected Apple event does not create
a Fall Guardian alert.

Raw algorithm defaults are `0.7 g` low acceleration, `2.5 g` impact,
`50°` orientation change, and `60 ms` minimum low-acceleration duration.
An impact alone never triggers: the detector also requires orientation change
or qualified low acceleration, followed by about two seconds of stillness.

Foreground cancellation requires a deliberate 1.5-second hold. The raw
detector stays active while the app is visible. Raw accelerometer streaming
stops when watchOS suspends the app, so the current custom detector does not
provide continuous background monitoring.

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

For a physical integration test, install a **debug** build on the paired
iPhone and Watch, open the Watch app, then choose **Test Apple relay (debug)**.
It invokes the exact app-side path used after `CMFallDetectionManager` reports
an event: WatchConnectivity, the iPhone native relay, the API, and its
30-second cancellation deadline. It does **not** emulate Apple's proprietary
fall sensor or prove that Apple will classify a particular movement as a fall.
Cancel from the Watch or iPhone before the deadline to verify that no caregiver
push notification is sent; let a separate, agreed test alert expire to verify
caregiver delivery.

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
- The API owns countdown, cancellation deadline, and caregiver notification.
- The assisted iPhone native relay submits an Apple Watch event before Flutter
  is available, then Flutter resumes the same idempotent alert when opened.
- Apple approved the Fall Detection capability and signed builds embed the
  entitlement. Simulator algorithm tests still do not replace locked-iPhone
  and physical-watch validation.

## Related Projects

- `../assisted_mobile`: assisted user mobile app.
- `../wear_os`: Wear OS counterpart.
- `../../backend/api`: backend API.
