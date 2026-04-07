// flutter/services.dart provides MethodChannel, the standard Flutter mechanism
// for calling native (Kotlin/Swift) code and receiving calls back from it.
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

// ─── Type aliases (typedefs) ──────────────────────────────────────────────────
// These give meaningful names to plain function signatures so the rest of the
// code reads like English ("a FallDetectedCallback is a function that takes an
// int timestamp and returns nothing") instead of raw `void Function(int)`.

/// A function that is called when the watch reports a fall.
/// [timestamp] is the Unix epoch in milliseconds at the moment of detection.
typedef FallDetectedCallback = void Function(int timestamp);

/// A function that is called when the watch (or any other device) cancels
/// the current alert.
typedef CancelAlertCallback = void Function();

// ─── Why a MethodChannel? ────────────────────────────────────────────────────
// Flutter runs inside a sandboxed Dart VM. To talk to Android or iOS APIs
// (Bluetooth, the Wear OS Data Layer, WatchConnectivity) we must cross the
// "platform boundary". Flutter's standard bridge for this is a MethodChannel.
//
// Both sides agree on a channel name (a plain string used as an identifier)
// and a set of method names. The native side can call into Dart ("you just
// got a fall event") and Dart can call into native ("please send this cancel
// to the watch"). All data is serialised automatically (maps, strings, ints).
//
// Architecture overview:
//   Watch hardware
//       │  (Wear OS Data Layer  OR  WCSession)
//       ▼
//   Native layer  (Kotlin on Android / Swift on iOS)
//       │  MethodChannel('fall_guardian/watch')
//       ▼
//   WatchCommunicationService  (this file, Dart)
//       │  callbacks
//       ▼
//   _FallGuardianAppState  →  FallAlertScreen

/// Single point of contact between the Flutter app and the native watch layer.
///
/// Responsibilities:
/// - Registers a MethodChannel handler to receive `onFallDetected` and
///   `onAlertCancelled` calls pushed up from the native platform code.
/// - Exposes static methods [sendCancelAlert] and [pushThresholds] so any
///   part of the Dart code can send a command down to the watch without
///   needing a reference to this service instance.
class WatchCommunicationService {
  // The channel name is a plain string that acts as an identifier.
  // The exact same string must appear in:
  //   • WearDataListenerService.kt  (Android)
  //   • WatchSessionManager.swift   (iOS)
  // If they don't match, the channel is silent and events are lost.
  static const _channel = MethodChannel('fall_guardian/watch');

  // Nullable callbacks — they start as null and are assigned by the caller
  // (the app root) before any events can arrive.
  FallDetectedCallback? _onFallDetected;
  CancelAlertCallback? _onCancelAlert;

  /// Creates the service and immediately registers the MethodChannel handler.
  ///
  /// The handler is set in the constructor (not lazily) because falls can be
  /// detected at any time — if we wait until the first screen is built, we
  /// might miss an event that arrived during startup.
  WatchCommunicationService() {
    // setMethodCallHandler tells the Flutter engine: "when native code calls
    // a method on this channel, invoke _handleMethod".
    _channel.setMethodCallHandler(_handleMethod);
  }

  /// Stores the callback to invoke when a fall is detected.
  /// Called once by the app root during [initState].
  void setFallDetectedCallback(FallDetectedCallback callback) {
    _onFallDetected = callback;
  }

  /// Stores the callback to invoke when an alert is remotely cancelled.
  /// Called once by the app root during [initState].
  void setCancelAlertCallback(CancelAlertCallback callback) {
    _onCancelAlert = callback;
  }

  /// Dispatches incoming native → Dart method calls to the right callback.
  ///
  /// This is the "receive" side of the MethodChannel bridge.
  /// [call.method] is the method name; [call.arguments] is the payload.
  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      // Native code calls 'onFallDetected' with a map containing 'timestamp'.
      // Example payload from Kotlin: {"timestamp": 1710000000000}
      case 'onFallDetected':
        final args = call.arguments as Map<Object?, Object?>?;
        // Safely extract the timestamp. If the native side forgot to include
        // it (shouldn't happen, but defensive coding), fall back to now.
        final ts =
            args?['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        // The `?.call(ts)` syntax means: invoke the function only if the
        // callback has been registered; otherwise do nothing silently.
        _onFallDetected?.call(ts);
        return null;

      // Native code calls 'onAlertCancelled' with no payload when the user
      // cancels the alert on the watch.
      case 'onAlertCancelled':
        _onCancelAlert?.call();
        return null;

      default:
        return null;
    }
  }

  /// Clears the channel handler and nulls the callbacks.
  ///
  /// Called when the root widget is permanently removed (app shutdown).
  /// Passing `null` to setMethodCallHandler unregisters the handler, which
  /// prevents the engine from delivering events to a garbage-collected object.
  void dispose() {
    _channel.setMethodCallHandler(null);
    _onFallDetected = null;
    _onCancelAlert = null;
  }

  // ── Outbound commands (Dart → Native → Watch) ─────────────────────────────
  // These are `static` because any widget can call them without needing a
  // reference to the service instance — they always target the same channel.

  /// Sends a cancel-alert signal to the connected watch(es).
  ///
  /// Flow:
  ///   1. Dart calls invokeMethod('sendCancelAlert') on the channel.
  ///   2. Android: native Kotlin sends a Wearable MessageClient message to
  ///      the Wear OS app, which stops its countdown.
  ///   3. iOS: native Swift calls WCSession.sendMessage / transferUserInfo,
  ///      which tells the watchOS app to stop its countdown.
  ///
  /// Silently no-ops if the watch is not connected or the platform rejects
  /// the call — a failed cancel is better than a crash, and the 30-second
  /// timeout is a safety net.
  static Future<void> sendCancelAlert() async {
    try {
      await _channel.invokeMethod('sendCancelAlert');
    } catch (error, stackTrace) {
      developer.log(
        'sendCancelAlert failed',
        name: 'WatchCommunicationService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Pushes detection threshold values to the connected watch(es).
  ///
  /// The watch's fall-detection algorithm uses four tunable numbers:
  ///   - [freeFall]  — minimum G-force drop that counts as free-fall.
  ///   - [impact]    — minimum G-force spike that counts as an impact landing.
  ///   - [tilt]      — maximum allowed tilt angle after impact.
  ///   - [freeFallMs] — minimum free-fall duration in milliseconds.
  ///
  /// The keys in the map below must exactly match the SharedPreferences keys
  /// used on the Wear OS side and the UserDefaults keys on watchOS.
  /// Changing any key here requires a matching change on both watch platforms.
  ///
  /// Silently no-ops if the watch is not connected or the platform rejects the call.
  static Future<void> pushThresholds({
    required double freeFall,
    required double impact,
    required double tilt,
    required int freeFallMs,
  }) async {
    try {
      await _channel.invokeMethod('sendThresholds', {
        // These string keys are the cross-platform contract — they must be
        // identical in Flutter, Wear OS Kotlin, and watchOS Swift.
        'thresh_freefall': freeFall,
        'thresh_impact': impact,
        'thresh_tilt': tilt,
        'thresh_freefall_ms': freeFallMs,
      });
    } catch (error, stackTrace) {
      developer.log(
        'pushThresholds failed',
        name: 'WatchCommunicationService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
