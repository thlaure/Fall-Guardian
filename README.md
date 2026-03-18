# Fall Guardian

A PSP-aware fall detection system for smartwatches that alerts family members by SMS when a fall is detected.

Built for people with **Progressive Supranuclear Palsy (PSP)** — a neurological condition causing frequent, atypical falls. Samsung's built-in fall detection requires prolonged immobility after a fall, which misses PSP falls entirely. Fall Guardian detects the fall event itself.

---

## How it works

1. The watch runs a continuous fall detection algorithm at 50 Hz
2. When a fall is detected, the phone displays a **30-second countdown**
3. The person can press **"I'm OK"** to cancel if it was a false alarm
4. If the countdown expires, the phone fetches GPS and **sends an SMS** to all saved emergency contacts with a Google Maps link

No server, no subscription, no internet required — just SMS.

---

## Features

### Watch app (Wear OS & Apple Watch)
- Continuous background fall monitoring at 50 Hz
- PSP-optimized algorithm: triggers on impact + orientation change, not immobility
- Configurable detection thresholds
- Persists across reboots (Wear OS auto-restarts on boot)
- "Monitoring active" status screen

### Phone app (Android & iOS)
- **Full-screen fall alert** with 30-second countdown and pulsing warning
- **One-tap cancel** ("I'm OK") for false alarms
- **Emergency contacts** — add, edit, remove family members with name + phone number
- **SMS alerts** — sends to all contacts simultaneously with GPS location link
- **Fall history** — log of every event with status (Alert Sent / Cancelled), location, and notified contacts
- **Sensitivity settings** — adjust all four detection thresholds with sliders
- Dark UI designed for quick, stressed interaction

---

## Architecture

```
┌─────────────────────────────────┐
│  Wear OS App (Kotlin)           │  Galaxy Watch
│  FallDetectionService           │
│  50 Hz accelerometer            │
│  PSP fall algorithm             │
└────────────┬────────────────────┘
             │ Wearable Data Layer API
┌────────────▼────────────────────┐
│  Android Phone App (Flutter)    │
│  WearDataListenerService        │
│  30s countdown · SMS · GPS      │
│  Contacts · History · Settings  │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  watchOS App (Swift)            │  Apple Watch
│  FallDetectionManager           │
│  CMMotionManager 50 Hz          │
│  PSP fall algorithm             │
└────────────┬────────────────────┘
             │ WatchConnectivity (WCSession)
┌────────────▼────────────────────┐
│  iOS Phone App (Flutter)        │
│  WatchSessionManager            │
│  (identical to Android app)     │
└─────────────────────────────────┘
```

> Flutter does not support watchOS or Wear OS. The watch apps are fully native (Kotlin / Swift). The phone app is shared Flutter code for both platforms.

---

## Repository structure

```
fall_guardian/
├── flutter_app/                        # Shared Flutter phone app
│   ├── lib/
│   │   ├── main.dart                   # App entry point, watch event routing
│   │   ├── screens/
│   │   │   ├── home_screen.dart        # Status + navigation
│   │   │   ├── fall_alert_screen.dart  # 30s countdown + cancel
│   │   │   ├── contacts_screen.dart    # Emergency contacts CRUD
│   │   │   ├── history_screen.dart     # Fall event log
│   │   │   └── settings_screen.dart    # Detection threshold sliders
│   │   ├── services/
│   │   │   ├── watch_communication_service.dart  # MethodChannel bridge
│   │   │   ├── sms_service.dart                  # Send SMS to contacts
│   │   │   ├── location_service.dart             # GPS location
│   │   │   └── notification_service.dart         # Full-screen alert notification
│   │   ├── models/
│   │   │   ├── contact.dart            # Contact model + JSON serialization
│   │   │   └── fall_event.dart         # Fall event model + status enum
│   │   └── repositories/
│   │       ├── contacts_repository.dart      # SharedPreferences persistence
│   │       └── fall_events_repository.dart   # SharedPreferences persistence
│   ├── android/
│   │   └── app/src/main/java/com/fallguardian/
│   │       ├── MainActivity.kt               # Flutter + MethodChannel host
│   │       └── WearDataListenerService.kt    # Wear OS Data Layer receiver
│   └── ios/
│       └── Runner/
│           ├── AppDelegate.swift             # Flutter + channel setup
│           └── WatchSessionManager.swift     # WCSession receiver
│
├── wear_os_app/                        # Native Kotlin Wear OS app
│   └── app/src/main/java/com/fallguardian/wear/
│       ├── FallDetectionService.kt     # Foreground service, sensor loop
│       ├── FallAlgorithm.kt            # 3-phase PSP detection algorithm
│       ├── WearDataSender.kt           # Data Layer → phone
│       ├── MainActivity.kt             # Compose status screen
│       └── BootReceiver.kt             # Auto-restart on reboot
│
└── watchos_app/                        # Native Swift watchOS app
    └── FallGuardian WatchKit Extension/
        ├── FallDetectionManager.swift  # CMMotionManager sensor loop
        ├── FallAlgorithm.swift         # 3-phase PSP detection algorithm
        ├── WatchSessionManager.swift   # WCSession → phone
        ├── ContentView.swift           # SwiftUI status screen
        └── FallGuardianApp.swift       # App entry point
```

---

## PSP fall detection algorithm

Standard fall detection waits for the person to stay on the ground. PSP patients often get back up immediately, or fall in a slow sideways topple with no clear free-fall phase. This algorithm fires on the fall event itself.

**Inputs:** Accelerometer at 50 Hz (+ gravity isolation via low-pass filter)

**Three phases:**

| Phase | Condition | Default threshold |
|-------|-----------|------------------|
| Free-fall | `‖accel‖ < 0.5g` sustained for ≥ 80ms | Configurable |
| Impact | `‖accel‖ > 2.5g` spike | Configurable |
| Tilt | Angle from upright > 45° (via gravity vector) | Configurable |

**Trigger rule:**

```
Fall detected = (FreeFall AND Impact) OR (Impact AND Tilt)
```

The OR branch (`Impact AND Tilt`) is the key PSP addition: a slow topple has no free-fall phase, but it does produce an impact spike and a large orientation change. No immobility check is performed — the alert fires immediately.

A **5-second cooldown** prevents duplicate events from the same fall.

The algorithm is implemented identically in Kotlin (`wear_os_app`) and Swift (`watchos_app`).

---

## Setup

### Prerequisites

| Tool | Purpose |
|------|---------|
| Flutter SDK ≥ 3.43 (beta channel) | Phone app |
| Android Studio | Wear OS app + Android phone |
| Xcode ≥ 26 | watchOS app + iPhone |
| Galaxy Watch (or emulator) | Wear OS testing |
| Apple Watch (or simulator) | watchOS testing |

> Flutter beta channel is required for iOS 26 simulator compatibility. Switch with `flutter channel beta && flutter upgrade`.

---

### 1. Flutter phone app

```bash
cd flutter_app
flutter pub get
flutter run                   # picks the connected device
flutter run -d emulator-5554  # explicit Android emulator
flutter run -d <ios-udid>     # explicit iOS simulator
```

**Android** — the `WearDataListenerService` is automatically registered in `AndroidManifest.xml`. No extra configuration needed; it receives Data Layer events when the phone and watch share the same Google account.

**iOS** — the `ios/` directory must exist (it is generated and committed). If it is missing, regenerate it with:
```bash
flutter create --platforms=ios --org com.fallguardian .
```
Then open `flutter_app/ios/Runner.xcworkspace` in Xcode to set your Team under *Signing & Capabilities* before running on a physical device.

---

### 2. Wear OS app

1. Open `wear_os_app/` in Android Studio
2. Connect a Galaxy Watch (USB or WiFi ADB) or start a Wear OS emulator
3. Run the `app` configuration
4. The fall detection service starts automatically and survives reboots

---

### 3. watchOS app

1. Open `watchos_app/` in Xcode
2. Set your Apple Developer Team under *Signing & Capabilities* for both the Watch Extension target and the companion iOS target
3. Update the Bundle Identifiers to match your iOS app (e.g. `com.yourname.fallguardian.watch`)
4. Run on Apple Watch simulator or a real device paired to the iPhone running the Flutter app

---

### Permissions

The phone app requests these at runtime:

| Permission | Platform | Used for |
|-----------|----------|----------|
| `SEND_SMS` | Android | Sending fall alerts |
| `ACCESS_FINE_LOCATION` | Android | GPS in alert SMS |
| Location (Always) | iOS | GPS in alert SMS |
| `POST_NOTIFICATIONS` | Android 13+ | Full-screen fall alert |
| `BODY_SENSORS` | Wear OS | Accelerometer access |

---

## Sensitivity tuning

Open **Settings** in the phone app to adjust thresholds. Changes are read by the watch service on next start.

| Setting | Lower value | Higher value |
|---------|------------|--------------|
| Free-fall threshold | More sensitive to small dips | Only very sharp drops trigger it |
| Impact threshold | Triggers on lighter impacts | Only hard hits trigger it |
| Tilt threshold | Triggers on small tilts | Only near-horizontal triggers it |
| Min free-fall duration | Triggers faster | Filters out very brief dips |

**Recommended starting point for PSP:**
- Free-fall: `0.5g` (or disable mentally — the tilt branch covers slow topples)
- Impact: `2.0g` (PSP falls aren't always violent)
- Tilt: `45°`
- Free-fall duration: `80ms`

If you get false positives from normal activity (hand gestures, sitting down hard), raise the impact threshold incrementally by `0.2g` until they stop.

---

## Unit tests

The Flutter app has unit and widget tests covering models, repositories, and the fall alert screen.

```bash
cd flutter_app
flutter test              # run all tests
flutter test --coverage   # with coverage report
```

Test files are under `flutter_app/test/`:

| File | What it covers |
|------|---------------|
| `models/contact_test.dart` | JSON serialization, `copyWith` |
| `models/fall_event_test.dart` | JSON serialization, all status values |
| `repositories/contacts_repository_test.dart` | add / remove / update / save |
| `repositories/fall_events_repository_test.dart` | add, newest-first sort, clear |
| `screens/fall_alert_screen_test.dart` | countdown render, cancel flow |

---

## Manual testing

### Verify detection
Hold the watch on your wrist, stand up straight, then quickly flick your arm downward and tilt your wrist to horizontal. This mimics the impact + tilt signature of a fall. The 30-second countdown should appear on the phone within 1–2 seconds.

### Verify false positive rejection
Shake the watch side-to-side rapidly (like waving goodbye). This produces acceleration spikes but no sustained tilt change. The alert should **not** trigger.

### Verify cancel flow
Let the countdown appear and press **"I'm OK"**. No SMS is sent. The event is logged in History as "Cancelled".

### Verify SMS flow
Add yourself as a test contact. Let the countdown expire. Verify you receive the SMS with a Google Maps link to your current location.

### Verify reboot persistence (Wear OS)
Restart the Galaxy Watch. Open the Fall Guardian app — it should be running without any extra taps (the `BootReceiver` starts it automatically).

---

## Dependencies

### Flutter (`flutter_app/pubspec.yaml`)

| Package | Version | Purpose |
|---------|---------|---------|
| `geolocator` | ^10.1.0 | GPS location |
| `flutter_sms` | ^3.0.1 | SMS sending |
| `shared_preferences` | ^2.2.2 | Contacts + settings persistence |
| `flutter_local_notifications` | ^17.0.0 | Full-screen fall alert notification |
| `uuid` | ^4.3.3 | Unique IDs for events and contacts |
| `intl` | ^0.20.2 | Date formatting in History screen |

### Wear OS (`wear_os_app/app/build.gradle`)

| Library | Purpose |
|---------|---------|
| `play-services-wearable` | Wearable Data Layer (send events to phone) |
| `androidx.wear.compose` | Watch UI |

### watchOS

| Framework | Purpose |
|-----------|---------|
| `CoreMotion` | Accelerometer at 50 Hz |
| `WatchConnectivity` | Send events to paired iPhone |
| `SwiftUI` | Watch status screen |

---

## Known limitations

- **SMS delivery is not guaranteed** in areas with no cellular coverage. The app logs the attempt regardless.
- **iOS background location** requires the user to grant "Always" location permission — "While Using" is not sufficient when the app is in the background.
- **watchOS background sensor access** uses the `workout-processing` background mode. If the watch suspends the app, detection pauses until the user opens it again. A future improvement would use `WKExtendedRuntimeSession`.
- The algorithm has not been validated in a clinical setting. Thresholds should be tuned for the individual.

---

## Roadmap

- [ ] `WKExtendedRuntimeSession` for continuous watchOS background monitoring
- [ ] Gyroscope integration for rotation-based fall confirmation
- [ ] Configurable countdown duration (10 / 20 / 30 / 60 seconds)
- [ ] WhatsApp / iMessage fallback when SMS fails
- [ ] Caregiver check-in: daily "I'm OK" confirmation with alert if not received
- [ ] Threshold auto-calibration based on the user's normal movement patterns
- [ ] Android companion app (non-Flutter) for deeper Wear OS integration
