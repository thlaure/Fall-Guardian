# Fall Guardian — Current Status

This file tracks temporary or fast-changing project status that should not live in the long-term architecture docs.

## Active limitations

- The Flutter app now submits timeout alerts to the backend, but real-device validation is still needed with a reachable backend URL instead of simulator localhost defaults.
- The current backend implementation still follows an SMS/fake-SMS delivery shape; the target production direction is caregiver-app push notifications.
- The caregiver app does not exist yet, so the repository is still in a transition state between emergency contacts and linked caregivers.
- Android local SMS should be treated only as an optional fallback, not as the main production path.
- Simulator iPhone/Apple Watch communication should not be treated as final product validation.
- Flutter iOS simulator builds can fail due to stale generated `.packages` symlink content under `flutter_app/ios/Flutter/ephemeral/Packages/`.

## Product direction

- Protected-person app: current Flutter phone app plus native watch apps.
- Caregiver app: planned dedicated mobile client for receiving and acknowledging alerts.
- Backend: source of truth for escalation, alert persistence, and future push notification delivery.
- Primary delivery target: backend-owned push notifications.
- Optional fallback: Android local SMS only when explicitly enabled.

## Build/tooling warnings

- `flutter_sms` does not yet support Swift Package Manager.
- `flutter_local_notifications` does not yet support Swift Package Manager.

## Validation standard

Before calling a safety-critical change done:
- run `make check`
- rebuild the affected phone target
- validate the flow on the relevant emulator/simulator
- prefer real-device validation for watch-to-phone behavior
