# Fall Guardian — Current Status

This file tracks temporary or fast-changing project status that should not live in the long-term architecture docs.

## Active limitations

- The Flutter app now submits timeout alerts to the backend, but real-device validation is still needed with a reachable backend URL instead of simulator localhost defaults.
- Simulator iPhone/Apple Watch communication should not be treated as final product validation.
- Flutter iOS simulator builds can fail due to stale generated `.packages` symlink content under `flutter_app/ios/Flutter/ephemeral/Packages/`.

## Build/tooling warnings

- `flutter_sms` does not yet support Swift Package Manager.
- `flutter_local_notifications` does not yet support Swift Package Manager.

## Validation standard

Before calling a safety-critical change done:
- run `make check`
- rebuild the affected phone target
- validate the flow on the relevant emulator/simulator
- prefer real-device validation for watch-to-phone behavior
