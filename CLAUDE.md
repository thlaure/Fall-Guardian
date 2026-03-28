# Fall Guardian — Claude context

Fall detection app for elderly/at-risk users. Watch detects a fall → 30-second alert on watch + push notification on phone (even if backgrounded) → if not cancelled within 30 s, sends SMS to emergency contacts.

## Product requirements (source of truth)

1. **Platforms**: iOS + watchOS (Apple Watch) and Android + Wear OS (Galaxy Watch). All 4 must stay in sync for every feature.
2. **Fall detection**: runs continuously on the watch as a foreground service (Wear OS) or background task (watchOS). Triggers on the watch, not the phone.
3. **Alert flow**:
   - Watch detects fall → starts 30-second countdown on watch + sends event to phone.
   - Phone shows `FallAlertScreen` (full-screen countdown) **if foregrounded**, AND always shows a push notification (even if the app is backgrounded or the screen is locked).
   - Watch and phone countdowns must be perfectly synchronised — same start timestamp, same remaining seconds.
   - Either device can cancel the alert; cancellation must propagate to the other device immediately.
4. **Sensitivity settings**: the phone app lets the user adjust detection thresholds (`thresh_freefall`, `thresh_impact`, `thresh_tilt`, `thresh_freefall_ms`). Changes are pushed to the watch immediately (or queued if offline).
5. **Emergency contacts**: managed in the phone app (name + phone number). Stored locally with SharedPreferences.
6. **SMS on timeout**: if 30 s elapse without cancellation, send an SMS to every emergency contact with a localised message including GPS coordinates if available.

## Repository layout

```
fall_guardian/
├── flutter_app/       # Flutter phone app (Android + iOS)
├── wear_os_app/       # Native Kotlin Wear OS app (Galaxy Watch)
└── watchos_app/       # Native Swift watchOS app (Apple Watch)
```

## Running / building

**Requirement:** Flutter beta channel (≥ 3.43) — needed for iOS 26 simulator.

```bash
# All 4 platforms via Makefile (from repo root)
make run-ios      # builds watchOS + runs Flutter on iPhone 17 simulator
make run-android  # runs Flutter on Android emulator (emulator-5554)
make run-wear     # runs Wear OS app on emulator (emulator-5556)
make check        # dart format + flutter test + flutter analyze

# Flutter only
cd flutter_app
flutter pub get
flutter run -d <device-id>
flutter test
flutter analyze
dart format lib/
```

## Key technical decisions

### iOS — UIScene lifecycle (iOS 26)
`ios/Runner/SceneDelegate.swift` opts into the UIScene lifecycle required by iOS 26. `AppDelegate.swift` conforms to `FlutterImplicitEngineDelegate` (required by Flutter 3.43+). Plugin registration and WatchConnectivity channel setup happen in `didInitializeImplicitFlutterEngine(_:)` via `engineBridge.pluginRegistry` and `engineBridge.applicationRegistrar.messenger()`. The old `applicationDidBecomeActive` approach causes a black screen on iOS 26.

### iOS — project file regeneration
The `ios/` directory (including `Runner.xcodeproj`) was generated via `flutter create --platforms=ios --org com.fallguardian .`. If it ever goes missing, that command recreates it. `WatchSessionManager.swift` must remain registered in `project.pbxproj` — it was added manually (UUIDs: file ref `B1C2D3E4F5A6B7C8D9E0F1A2`, build file `A1B2C3D4E5F6A7B8C9D0E1F2`).

### Android — Kotlin DSL gradle
The Android project uses `build.gradle.kts` (Kotlin DSL). Core library desugaring is enabled because `flutter_local_notifications` requires it on Android.

### Watch ↔ phone communication

**Android/Wear OS:**
- `WearDataListenerService` (registered in `AndroidManifest.xml`) receives Data Layer messages from the Wear OS app and forwards them to Flutter via `MethodChannel("fall_guardian/watch")`.

**iOS/watchOS:**
- `WatchSessionManager` (iOS, registered in `project.pbxproj`) receives WCSession messages and forwards them to Flutter via the same channel name.
- `WatchSessionManager` (watchOS) sends fall events and cancel signals via `sendMessage` (real-time) → `transferUserInfo` (offline fallback) → `updateApplicationContext` (persistent state).

**Simulator IPC workaround** — WCSession is broken between iOS and watchOS simulators deployed via `xcrun simctl`:
- Phone → watch cancel: phone writes `/tmp/com.fallguardian.cancelAlert`; watchOS polls it every 2 s.
- Watch → phone cancel: watchOS writes `/tmp/com.fallguardian.cancelFromWatch`; iOS polls it every 1 s.
- Both poll tasks are wrapped in `#if targetEnvironment(simulator)` — no impact on real devices.

### Notification on fall (background)
`flutter_local_notifications` shows a heads-up notification when `onFallDetected` fires and the app is not in the foreground (`WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed`). This ensures the user sees the alert even with the phone locked.

### Alert synchronisation
Both watch and phone use the same `fallTimestamp` (ms since epoch) as the countdown origin. The phone's `FallAlertScreen` starts its timer from `DateTime.now()` difference with that timestamp to stay in sync even if there is network latency.

## Flutter app structure

```
lib/
├── main.dart                          # entry point, fall event routing, cancel stream
├── l10n/                              # English + French localizations
├── models/                            # Contact, FallEvent (pure Dart)
├── repositories/                      # SharedPreferences persistence
├── screens/                           # home, fall_alert, contacts, history, settings
└── services/                          # watch_communication, sms, location, notification
```

## Test structure

```
test/
├── models/           # unit tests — JSON round-trips, copyWith
├── repositories/     # unit tests — SharedPreferences (mocked)
└── screens/          # widget tests — FallAlertScreen countdown + cancel
```

Repository tests use `SharedPreferences.setMockInitialValues({})`.
Widget tests mock the `flutter_local_notifications` MethodChannel (`dexterous.com/flutter/local_notifications`).

## Done checklist (run before every commit)

```bash
make check   # dart format + flutter test + flutter analyze
/review      # full code review on changed files
```

- [ ] `make check` passes
- [ ] `/review` run — all 🔴 Critical findings fixed, 🟡 Warnings addressed
- [ ] Tests updated for any changed logic
- [ ] All 4 platforms checked for required mirror changes (Flutter ↔ Android / iOS / watchOS / Wear OS)
- [ ] No `setState` / `invokeMethod` after an `await` without a `mounted` / `[weak self]` guard

## Cross-platform invariants

- **Threshold keys** must stay identical across Flutter `SharedPreferences`, Wear OS `SharedPreferences`, and watchOS `UserDefaults`: `thresh_freefall`, `thresh_impact`, `thresh_tilt`, `thresh_freefall_ms`
- **Watch MethodChannel**: `fall_guardian/watch`
  - Native → Flutter: `onFallDetected` (with `timestamp` ms), `onAlertCancelled`
  - Flutter → Native: `sendThresholds` (map of threshold keys above), `sendCancelAlert`
- **Phone → watch threshold sync**: Flutter `MethodChannel.invokeMethod('sendThresholds')` → native sends via Wearable `MessageClient` (`/thresholds`) or WCSession → native prefs/UserDefaults → listener reloads algorithm without restart. `transferUserInfo` is the offline fallback on iOS/watchOS.
- **Alert cancel propagation**: cancelling on either device must call `sendCancelAlert` toward the other. The receiving side calls `onAlertCancelled` on Flutter via the MethodChannel. Use `notifyPhone: false` / skip `sendCancelAlert` when the cancel originates from the other device to avoid ping-pong.
- **Permission handling standard**: request at launch (`ActivityResultContracts`), expose a Compose/SwiftUI state flag, show a dedicated error screen with a settings deep-link — never silently stop the service.

## Known issues / watch-outs

- **`flutter_sms`** and **`flutter_local_notifications`** do not yet support Swift Package Manager — this produces a warning but is not an error.
- **`geolocator` v10** API: use `desiredAccuracy` / `timeLimit` parameters, not `locationSettings` (added in v11).
- The `ios/Runner/Info.plist` must include `CFBundleExecutable`, `UIApplicationSceneManifest`, and `UIMainStoryboardFile = Main` — these were missing from the original file and caused install/black-screen failures.
- `FallAlertScreen` uses `PopScope(canPop: false)` to prevent accidental back navigation during the countdown — only programmatic `Navigator.pop()` dismisses it.
- `Task.sleep(for: .seconds(n))` requires iOS 16+. Use `Task.sleep(nanoseconds: n * 1_000_000_000)` in iOS native code for compatibility with the project's deployment target.
- Xcode DerivedData for the Flutter Runner can become corrupt when switching simulator targets. Fix: `flutter clean` + `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*`.
