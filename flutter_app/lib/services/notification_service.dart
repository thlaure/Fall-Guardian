// flutter_local_notifications is a Flutter plugin that wraps the native
// notification APIs on each platform:
//   Android — NotificationManager + NotificationChannel (required since Android 8)
//   iOS     — UNUserNotificationCenter (UserNotifications framework)
//
// "Local" means the notification is generated on the device itself (by our app)
// rather than sent from a server (which would be a "push" / "remote" notification).
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── Why this service exists ─────────────────────────────────────────────────
// We need to show the user an alert even when the app is in the background
// (screen locked, app not visible). The FallAlertScreen widget can only be
// shown when the app is in the foreground; an OS-level notification is the
// only way to reach the user when the screen is off or the app is hidden.
//
// This service centralises all notification logic so that:
//   • initialisation happens exactly once (guarded by _initialized).
//   • the rest of the app never touches the plugin directly.
//   • tests can stub this class without patching the plugin globally.

/// Manages OS-level local push notifications for Fall Guardian.
///
/// Usage order:
///   1. Call [initialize] once at app startup (in `main()`).
///   2. Call [showFallDetectedNotification] when a fall is detected and the
///      app is in the background.
///   3. Call [cancelAll] when the alert is resolved (cancelled or SMS sent)
///      to remove the notification from the notification shade.
class NotificationService {
  // ── Singleton plugin instance ─────────────────────────────────────────────
  // `static final` means there is exactly one plugin object for the entire
  // app lifetime, shared across all NotificationService instances.
  // This is important because the plugin registers itself with the OS during
  // initialization; creating multiple instances would cause conflicts.
  static final _plugin = FlutterLocalNotificationsPlugin();

  // A flag that prevents initialize() from registering the notification channel
  // with the OS more than once. Calling the underlying platform API twice is
  // harmless on iOS but can produce warnings on Android.
  static bool _initialized = false;

  // ── Android notification channel ──────────────────────────────────────────
  // Android 8+ requires every notification to belong to a "channel" — a named
  // category that users can independently enable/disable in Settings.
  // The channel ID is a stable identifier; the name is the human-readable label
  // shown in Android Settings → Notifications → Fall Guardian.
  static const _channelId = 'fall_guardian_alerts';
  static const _channelName = 'Fall Alerts';

  // ── Initialization ────────────────────────────────────────────────────────

  /// Initialises the notification plugin for both Android and iOS.
  ///
  /// Must be called once before any notification can be shown.
  /// Subsequent calls are no-ops (guarded by [_initialized]).
  ///
  /// On Android: registers the notification channel with the OS.
  /// On iOS:     requests permission to show alerts, badges, and play sounds.
  Future<void> initialize() async {
    // Early-exit guard — see _initialized explanation above.
    if (_initialized) return;

    // ── Android configuration ─────────────────────────────────────────────
    // The icon name '@mipmap/ic_launcher' refers to the app launcher icon
    // already included in the Android project (android/app/src/main/res/mipmap-*/).
    // This icon appears in the notification shade on Android.
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ── iOS configuration ─────────────────────────────────────────────────
    // DarwinInitializationSettings covers both iOS and macOS ("Darwin" is the
    // Unix base of Apple's OSes). The three `request*Permission` flags trigger
    // the system permission prompt the first time the app launches.
    //   requestAlertPermission: show banners and lock-screen notifications.
    //   requestBadgePermission: show a number badge on the app icon.
    //   requestSoundPermission: play a sound with each notification.
    // The user can later revoke any of these in Settings → Notifications.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combine both configs into a single InitializationSettings object and
    // hand it to the plugin. The plugin calls the matching native code on
    // whichever platform the app is currently running on.
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Mark as done so future calls (e.g. from tests or hot restarts) skip
    // the initialization and avoid double-registration side effects.
    _initialized = true;
  }

  // ── Showing a notification ─────────────────────────────────────────────────

  /// Shows the fall-detected notification with localized strings.
  ///
  /// This is shown only when the app is in the background (screen locked or
  /// app not visible). When the app is in the foreground, [FallAlertScreen]
  /// is pushed directly and no notification is needed.
  ///
  /// [title] and [body] are pre-built by the caller using [AppLocalizations]
  /// because this service class has no BuildContext.
  Future<void> showFallDetectedNotification({
    required String title,
    required String body,
  }) async {
    // ── Android notification details ──────────────────────────────────────
    const androidDetails = AndroidNotificationDetails(
      _channelId,   // must match the channel registered in initialize()
      _channelName, // displayed in Android notification settings
      // Importance.max + Priority.high together produce a "heads-up" notification
      // — the banner that slides in from the top of the screen even when the
      // phone is unlocked. This is the highest-priority notification type on Android.
      importance: Importance.max,
      priority: Priority.high,
      // fullScreenIntent: true attempts to launch the full-screen notification
      // activity on Android when the device is locked. This is what makes the
      // phone "wake up" and show the alert on the lock screen, similar to an
      // incoming call. Requires the USE_FULL_SCREEN_INTENT permission in the
      // AndroidManifest, which Flutter's plugin adds automatically.
      fullScreenIntent: true,
    );

    // ── iOS notification details ──────────────────────────────────────────
    const iosDetails = DarwinNotificationDetails(
      // presentAlert: show the notification banner on iOS.
      presentAlert: true,
      // presentSound: play the default notification sound.
      presentSound: true,
      // Note: presentBadge is not set here — we don't increment the badge
      // count for an alert that must be acted upon immediately.
    );

    // Send the notification to the OS. The `1` is the notification ID —
    // a stable integer that identifies this notification. Using the same ID
    // (1) for every fall notification means a new fall event replaces the
    // previous one instead of stacking multiple banners.
    await _plugin.show(
      1, // notification ID
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Cancellation ──────────────────────────────────────────────────────────

  /// Removes all active Fall Guardian notifications from the notification shade.
  ///
  /// Called after the alert is resolved (either cancelled or SMS sent) so the
  /// user isn't left with a stale "Fall Detected" banner in their notification
  /// shade after the situation has already been handled.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
