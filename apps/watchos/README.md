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
-> native detector evaluates fall threshold
-> watch app marks a possible fall
-> watch sends event to assisted iPhone
-> assisted app owns countdown and escalation
```

The watch app does not call the backend and does not notify caregivers directly.

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
- `FallGuardianTests/FallAlgorithmTests.swift`: algorithm tests.

## Requirements

- Xcode.
- watchOS simulator or compatible Apple Watch.
- iPhone companion/runtime context when validating phone communication.

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

Direct Xcode test command:

```sh
xcodebuild -project FallGuardian/FallGuardian.xcodeproj -scheme "FallGuardian Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' test
```

## Testing Guidance

Prioritize tests around:

- fall algorithm threshold behavior;
- normal motion that must not trigger a fall;
- edge cases around sensor spikes;
- watch-to-phone message payloads;
- lifecycle behavior when the watch app is paused or resumed.

## Sensor And Safety Notes

- Keep threshold logic explicit and easy to review.
- Any UI threshold setting must affect the real detection rule.
- Avoid battery-heavy sampling unless required for reliable detection.
- The assisted iPhone owns countdown, cancellation, backend submission, and
  caregiver notification.

## Related Projects

- `../assisted_mobile`: assisted user mobile app.
- `../wear_os`: Wear OS counterpart.
- `../../backend/api`: backend API.
