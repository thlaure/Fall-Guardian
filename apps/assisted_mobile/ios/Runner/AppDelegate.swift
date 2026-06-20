// UIKit is Apple's core UI framework for iOS apps — it manages the app lifecycle,
// windows, view controllers, and user interface elements.
import UIKit

// Flutter is the cross-platform framework we use for the phone app's UI and logic.
// Importing it here gives us access to Flutter's engine types and plugin registration.
import Flutter
import Security

// WatchConnectivity is Apple's framework for phone ↔ Apple Watch communication.
// It must be imported here because AppDelegate sets up the WatchSessionManager,
// which is responsible for all WCSession messaging.
import WatchConnectivity

// MARK: - AppDelegate
//
// What is AppDelegate?
// Every iOS app has exactly one AppDelegate. It is the first Swift class that iOS
// instantiates when your app process starts. It receives system-level lifecycle
// events: app launched, app backgrounded, app terminated, etc.
//
// @main tells the Swift compiler "this is the entry point of the app".
// Without it, iOS would not know where to start.
//
// @objc exposes the class to Objective-C, which is required because UIKit and
// Flutter's internals are still partly written in Objective-C.
//
// FlutterAppDelegate is a subclass of UIResponder/UIApplicationDelegate provided
// by the Flutter SDK. It wires up the Flutter engine to iOS app lifecycle events
// automatically (e.g. memory warnings, background fetch).
//
// FlutterImplicitEngineDelegate is a protocol (like an interface in Java/Dart)
// introduced in Flutter 3.43 for the UIScene lifecycle used on iOS 26.
// It replaces the old approach of setting up Flutter in applicationDidBecomeActive,
// which causes a black screen on iOS 26 because UIScene takes over window management
// before that callback fires.

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    // MARK: - Stored Properties

    // FlutterMethodChannel is a named communication pipe between Swift and Dart.
    // Think of it like a named socket: both sides agree on the name
    // ("fall_guardian/watch") and can send method calls back and forth.
    // This channel carries:
    //   Swift → Dart : "onFallDetected", "onAlertCancelled"
    //   Dart → Swift : "sendThresholds", "sendCancelAlert"
    // Optional (?) because it is only created once the Flutter engine is ready
    // (see didInitializeImplicitFlutterEngine below).
    private var channel: FlutterMethodChannel?
    private var secureStorageChannel: FlutterMethodChannel?

    // WatchSessionManager is our own class (WatchSessionManager.swift) that wraps
    // WCSession. It handles all Apple Watch ↔ phone message routing.
    // Stored here as a strong reference so it is not deallocated for the lifetime
    // of the app.
    private var watchSession: WatchSessionManager?
    private let secureStorageService = "com.fallguardian.secure-store"

    // MARK: - UIApplicationDelegate

    /// Called by iOS immediately after the app process launches.
    ///
    /// On iOS 26 with UIScene lifecycle, the window and Flutter engine are NOT yet
    /// ready here — that happens in SceneDelegate. We only call super so that
    /// FlutterAppDelegate can do its own internal setup (plugin lookup tables, etc.).
    /// Do NOT try to access Flutter channels here; they don't exist yet.
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Request notification permission natively.
        // We deliberately do NOT call flutter_local_notifications.initialize() on iOS
        // (see notification_service.dart) because the plugin sets itself as the
        // UNUserNotificationCenterDelegate and then suppresses notifications it did
        // not post itself — including our native fall alert.  Requesting permission
        // here and setting AppDelegate as the permanent delegate avoids that conflict.
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                NSLog("[Notifications][Phone] requestAuthorization failed: \(error)")
                return
            }
            NSLog("[Notifications][Phone] requestAuthorization granted=\(granted)")
        }

        // Become the notification center delegate before any plugin can take it.
        // willPresent (below) ensures fall banners are shown even in the foreground.
        UNUserNotificationCenter.current().delegate = self

        // Start WCSession BEFORE Flutter initialises so fall events sent by the
        // watch via transferUserInfo can be received even when the app is woken
        // from a killed state (background delivery). The Flutter channel is not
        // available yet; WatchSessionManager stores any arriving fall event in
        // UserDefaults and shows a native notification until Flutter is ready.
        watchSession = WatchSessionManager()
        watchSession?.startSession()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show local notifications as a banner with sound when they are delivered
    /// while the app is foregrounded.
    ///
    /// flutter_local_notifications is not initialised on iOS (so it never
    /// overrides this delegate), meaning this method is the single authority
    /// over foreground notification presentation for the whole app.
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    // MARK: - FlutterImplicitEngineDelegate

    /// Called by the Flutter SDK once the Flutter engine has fully initialised.
    ///
    /// This is the correct place (on iOS 26 / Flutter 3.43+) to:
    ///   1. Register all Flutter plugins (camera, notifications, etc.)
    ///   2. Create the MethodChannel that links Swift ↔ Dart
    ///   3. Start the WCSession so the Apple Watch can connect
    ///   4. Set up the handler that receives Dart → Swift method calls
    ///
    /// Why here and not in application(_:didFinishLaunchingWithOptions:)?
    /// With UIScene lifecycle the Flutter engine is owned by the scene, not the
    /// application. It finishes initialising asynchronously after the scene connects,
    /// so the engine (and its messenger) is guaranteed to exist only at this point.
    ///
    /// - Parameter engineBridge: Provided by Flutter — gives access to the plugin
    ///   registry and the binary messenger needed to create channels.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {

        // Step 1 — Register all Flutter plugins declared in pubspec.yaml.
        // GeneratedPluginRegistrant is auto-generated by `flutter pub get`. It
        // iterates over every Flutter plugin (flutter_local_notifications, geolocator,
        // etc.) and tells the Flutter engine about the native side of each plugin.
        // engineBridge.pluginRegistry is the object that keeps track of all plugins.
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // Step 2 — Create the MethodChannel for watch communication.
        // The channel name "fall_guardian/watch" is a shared constant; it MUST match
        // exactly in Dart (lib/services/watch_communication.dart).
        // binaryMessenger is the low-level transport that serialises method call
        // arguments (as binary data) and dispatches them on the right thread.
        channel = FlutterMethodChannel(
            name: "fall_guardian/watch",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        secureStorageChannel = FlutterMethodChannel(
            name: "fall_guardian/secure_storage",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )

        // Step 3 — Wire the Flutter channel into the already-running WatchSessionManager.
        // watchSession was created early in application(_:didFinishLaunchingWithOptions:)
        // so WCSession is active even before Flutter starts. Now that the engine is
        // ready, inject the channel and drain any fall event that arrived during a
        // background wakeup (e.g. app was killed, watch sent transferUserInfo, iOS
        // woke the app in the background, WatchSessionManager stored the timestamp
        // in UserDefaults). drainPendingFallEvent() forwards it to Flutter and cancels
        // the native wake-up notification so FallAlertScreen can take over.
        watchSession?.setChannel(channel!)
        watchSession?.drainPendingFallEvent()
        watchSession?.drainPendingAlertCancel()

        // Step 4 — Listen for method calls coming FROM Dart (the Flutter side).
        // [weak self] prevents a retain cycle: if AppDelegate is ever deallocated,
        // the closure will not keep it alive (and will safely do nothing).
        channel!.setMethodCallHandler { [weak self] call, result in

            // call.method is the string name of the method Dart invoked.
            switch call.method {

            // Dart calls "sendThresholds" when the user changes sensitivity settings
            // in the phone app. The arguments are a dictionary like:
            //   { "thresh_freefall": 2.0, "thresh_impact": 3.5, ... }
            // We forward them to WatchSessionManager which sends them to the watch.
            case "sendThresholds":
                if let args = call.arguments as? [String: Any] {
                    self?.watchSession?.sendThresholds(args)
                }

            // Dart calls "sendCancelAlert" when the user taps "I'm OK" on the phone.
            // WatchSessionManager will propagate the cancellation to the Apple Watch.
            case "sendCancelAlert":
                self?.watchSession?.sendCancelAlert()

            default:
                break
            }

            // result(nil) tells Flutter the method call completed with no return value.
            // This is mandatory — if we omit it Flutter would show a "method not
            // implemented" error on the Dart side.
            result(nil)
        }

        secureStorageChannel!.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "NO_APP", message: "AppDelegate unavailable", details: nil))
                return
            }

            let args = call.arguments as? [String: Any]
            let key = args?["key"] as? String

            switch call.method {
            case "read":
                guard let key else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
                    return
                }
                result(self.readSecureValue(forKey: key))
            case "write":
                guard let key, let value = args?["value"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing key/value", details: nil))
                    return
                }
                let status = self.writeSecureValue(value, forKey: key)
                if status == errSecSuccess {
                    result(nil)
                } else {
                    result(FlutterError(code: "SECURE_WRITE_FAILED", message: "Keychain write failed", details: status))
                }
            case "delete":
                guard let key else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing key", details: nil))
                    return
                }
                let status = self.deleteSecureValue(forKey: key)
                if status == errSecSuccess || status == errSecItemNotFound {
                    result(nil)
                } else {
                    result(FlutterError(code: "SECURE_DELETE_FAILED", message: "Keychain delete failed", details: status))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func secureQuery(forKey key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: secureStorageService,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    private func readSecureValue(forKey key: String) -> String? {
        var query = secureQuery(forKey: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeSecureValue(_ value: String, forKey key: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }

        let deleteStatus = deleteSecureValue(forKey: key)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            return deleteStatus
        }

        var query = secureQuery(forKey: key)
        query[kSecValueData] = data
        return SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteSecureValue(forKey key: String) -> OSStatus {
        SecItemDelete(secureQuery(forKey: key) as CFDictionary)
    }
}
