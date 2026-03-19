# Fall Guardian — Claude context

PSP-aware fall detection app. Watch detects fall → phone shows 30s countdown → SMS to emergency contacts if not cancelled.

## Repository layout

```
fall_guardian/
├── flutter_app/       # Flutter phone app (Android + iOS)
├── wear_os_app/       # Native Kotlin Wear OS app (Galaxy Watch)
└── watchos_app/       # Native Swift watchOS app (Apple Watch)
```

## Running the Flutter app

**Requirement:** Flutter beta channel (≥ 3.43) — needed for iOS 26 simulator.

```bash
cd flutter_app
flutter channel beta   # if not already on beta
flutter pub get
flutter run            # auto-selects connected device
flutter test           # run all unit + widget tests
flutter analyze        # static analysis
dart format lib/       # auto-format
```

## Key technical decisions

### iOS — UIScene lifecycle (iOS 26)
`ios/Runner/SceneDelegate.swift` opts into the UIScene lifecycle required by iOS 26. `AppDelegate.swift` conforms to `FlutterImplicitEngineDelegate` (required by Flutter 3.43+). Plugin registration and WatchConnectivity channel setup happen in `didInitializeImplicitFlutterEngine(_:)` via `engineBridge.pluginRegistry` and `engineBridge.applicationRegistrar.messenger()`. The old `applicationDidBecomeActive` approach causes a black screen on iOS 26.

### iOS — project file regeneration
The `ios/` directory (including `Runner.xcodeproj`) was generated via `flutter create --platforms=ios --org com.fallguardian .`. If it ever goes missing, that command recreates it. `WatchSessionManager.swift` must remain registered in `project.pbxproj` — it was added manually (UUIDs: file ref `B1C2D3E4F5A6B7C8D9E0F1A2`, build file `A1B2C3D4E5F6A7B8C9D0E1F2`).

### Android — Kotlin DSL gradle
The Android project uses `build.gradle.kts` (Kotlin DSL). Core library desugaring is enabled because `flutter_local_notifications` requires it on Android.

### Watch communication
- **Android:** `WearDataListenerService` (registered in `AndroidManifest.xml`) receives Data Layer messages from the Wear OS app and forwards them to Flutter via `MethodChannel("fall_guardian/watch")`.
- **iOS:** `WatchSessionManager` (registered in `project.pbxproj`) receives WCSession messages and forwards them to Flutter via the same channel name.

## Flutter app structure

```
lib/
├── main.dart                          # entry point, fall event routing
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

## Known issues / watch-outs

- **`flutter_sms`** and **`flutter_local_notifications`** do not yet support Swift Package Manager — this produces a warning but is not an error.
- **`geolocator` v10** API: use `desiredAccuracy` / `timeLimit` parameters, not `locationSettings` (that was added in v11).
- The `ios/Runner/Info.plist` must include `CFBundleExecutable`, `UIApplicationSceneManifest`, and `UIMainStoryboardFile = Main` — these were missing from the original file and caused install/black-screen failures.
- `FallAlertScreen` uses `PopScope(canPop: false)` to prevent accidental back navigation during the countdown — only programmatic `Navigator.pop()` dismisses it.
