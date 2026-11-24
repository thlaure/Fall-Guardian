# Fall Guardian watchOS App

Native watchOS app for Apple Watch fall detection and alert handoff to the
assisted iPhone.

## Responsibilities

- Receive Apple's system fall events (`CMFallDetectionManager`).
- Show watch-side detection/alert state.
- Send fall events to the assisted iPhone.
- Keep detection thresholds and event contracts aligned with the assisted app.

## Runtime Flow

```text
Apple system detects a serious fall while the app is foregrounded or suspended
-> CMFallDetectionManager wakes the Watch extension
-> Watch generates an incidentId, shows its alert, and sends one idempotent event to iPhone
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
offers **I'm OK — Open to cancel**. Neither the notification tap nor the action
cancels anything: both open the app on its alert screen, where cancelling
always requires the deliberate 1.5-second hold.

The alert screen counts down from the fall time (the same origin used by the
phone and API). Apple delivers its event only after its own check-in prompt, so
the 30-second window may already be over when the watch receives it. The
screen then shows **Notifying your caregivers…** instead of a 0 countdown, and
the hold-to-cancel stays available for at least 30 seconds after the alert is
shown. Escalation timing is unchanged: the API owns the deadline; a late cancel
is relayed and the API decides what it still means.

Time-sensitive delivery lets the alert break through Focus (it still respects
silent mode). Bypassing silent mode would require Apple's separately approved
Critical Alerts entitlement.

### Apple resolution handling

`CMFallDetectionEvent.resolution` decides what Fall Guardian does
(`SystemFallPolicy` in `WatchAlertDeadline.swift`):

| Resolution | Meaning | Fall Guardian |
| --- | --- | --- |
| `confirmed` | wearer said they fell and need help | alert + relay to iPhone |
| `unresponsive` | wearer did not answer Apple's prompt | alert + relay to iPhone |
| unknown future value | — | alert + relay (safety first) |
| `dismissed` | wearer fell but answered "I'm OK" | no alert, recorded locally only |
| `rejected` | wearer said they did not fall | ignored |

`dismissed` is not forwarded: the phone contract has no "resolved without
alert" event, and an `alert_cancelled` for an incident the phone never saw could
cancel a different, real incident on phone builds that ignore `incidentId`.

### WatchConnectivity contract

Keys are only ever added, so the current iPhone app keeps working.

| Direction | Payload |
| --- | --- |
| watch → phone | `event=fall_detected`, `timestamp` (ms), `incidentId` (lowercase UUID) |
| watch → phone | `event=alert_cancelled`, `fallTimestamp` (ms), `incidentId` |
| phone → watch | `event=alert_cancelled`, `fallTimestamp`, optional `incidentId` |
| phone → watch (context) | `alertCancelled`, `fallTimestamp`, optional `incidentId` |
| phone → watch | `event=set_thresholds` — handled in DEBUG builds only |

An incoming cancel carrying `incidentId` is accepted only when it matches the
active alert; without one, `fallTimestamp` must match (previous behaviour).

### Time-sensitive notification entitlement

The entitlements file declares
`com.apple.developer.usernotifications.time-sensitive` next to the approved
`com.apple.developer.health.fall-detection`. Both projects that build the watch
app (`FallGuardian.xcodeproj` and `apps/assisted_mobile/ios/Runner.xcodeproj`)
use automatic signing, so Xcode enables the capability on the App ID and
regenerates the profile on the next device build or archive. Command-line
device builds need `-allowProvisioningUpdates` for that. Simulator builds are
unaffected.

If automatic provisioning fails (for example "Provisioning profile doesn't
include the com.apple.developer.usernotifications.time-sensitive entitlement"):

1. Apple Developer portal → Certificates, Identifiers & Profiles → Identifiers
   → `com.fallguardian.app.watchkitapp`.
2. Enable **Time Sensitive Notifications**, keep **Fall Detection** enabled,
   save.
3. Profiles → regenerate (edit + save) every profile for that App ID, or let
   Xcode do it: Signing & Capabilities → toggle "Automatically manage signing"
   off and on, then build to a device once.
4. Rebuild and confirm with
   `codesign -d --entitlements - "FallGuardian Watch App.app"` that both
   entitlements are present.

Apple's `CMFallDetectionManager` is the supported background trigger. It needs
Apple's Fall Detection entitlement and the wearer's permission. Apple owns its
own emergency/SOS flow; Fall Guardian only starts its separate caregiver grace
window after receiving the system event. A rejected Apple event does not create
a Fall Guardian alert.

Foreground cancellation requires a deliberate 1.5-second hold. Apple system
detection is the only production source. The custom raw-accelerometer detector
(`FallAlgorithm`, `FallDetectionManager`) is compiled in DEBUG builds only, is
not started by the app, and is kept for physical tuning experiments and its
unit tests; `set_thresholds` is ignored outside DEBUG. If Apple
detection is unavailable or the wearer denies permission, the app reports that
monitoring is inactive instead of implying background protection.

The next increment is to consume the one-time enrollment sent by the iPhone,
claim watch-specific credentials, and store them in Keychain. See
`../../docs/COMPANION_ENROLLMENT.md`.

## Project Layout

```text
apps/watchos/
├── FallGuardian/
│   ├── FallGuardian.xcodeproj
│   └── FallGuardian Watch App/
├── FallGuardianTests/       XCTest suites run by `swift test`
├── Package.swift            host test harness for the pure logic files
├── scripts/check_coverage.py
└── Makefile
```

Core source files include:

- `ContentView.swift`: watch UI and its thin view model.
- `FallGuardianApp.swift`: app delegate, notifications, Apple fall detection.
- `WatchAlertDeadline.swift`: pure, unit-tested logic — deadlines, incident
  identity, WatchConnectivity payloads, cancel matching, resolution policy,
  alert state machine. Kept in this existing file because
  `Runner.xcodeproj` compiles an explicit list of watch source files.
- `WatchSessionManager.swift`: communication with the iPhone.
- `FallAlgorithm.swift`, `FallDetectionManager.swift`: DEBUG-only custom
  detector.
- `Localizable.xcstrings`, `InfoPlist.xcstrings`: English and French strings.

Note: `Runner.xcodeproj` (the production build) does not yet reference the
two string catalogs or the `fr` region; until it does, that build falls back to
English text.

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
make test       # swift test (XCTest) on the macOS host, with coverage data
make coverage   # test + line-coverage gate (MIN_COVERAGE, default 93%)
make analyze
make build
```

Without an installed watchOS simulator runtime, use the generic destination:

```sh
make check DESTINATION='generic/platform=watchOS Simulator'
```

## Testing Guidance

For a physical integration test, install a **debug or profile test** build on the paired
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
- notification action opening the hold-to-cancel screen;
- countdown restoration after opening a fall notification;
- late Apple delivery showing "Notifying your caregivers…".

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
