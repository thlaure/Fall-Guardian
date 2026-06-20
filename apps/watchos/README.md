# Fall Guardian watchOS App

Native watchOS app for watch-side fall detection and alert handoff.

## Responsibilities

- run fall detection on Apple Watch using watch sensors
- start the watch-side alert experience
- communicate fall events to the assisted user's iPhone
- keep watch contracts aligned with the assisted app

## Requirements

- Xcode
- watchOS Simulator or compatible Apple Watch
- iPhone companion/runtime context when testing phone communication

## Project

The Xcode project lives at:

```text
FallGuardian/FallGuardian.xcodeproj
```

Core source areas:

- `FallGuardian/FallGuardian Watch App/`
- `FallGuardianTests/`

## Verification

Use the active simulator name available in your local Xcode installation:

```sh
xcodebuild -project FallGuardian/FallGuardian.xcodeproj -scheme FallGuardian -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' test
```

Run a simulator/device build when changing capabilities, entitlements, sensors,
or phone communication.

## Related Repositories

- `../assisted_mobile`: assisted user mobile app
- `../wear_os`: Wear OS counterpart
- `../../backend/api`: backend API
