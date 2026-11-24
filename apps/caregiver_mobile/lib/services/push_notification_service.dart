import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

import 'caregiver_backend_service.dart';
import 'pending_alert_store.dart';

/// Kinds of push messages the caregiver app reacts to.
enum PushKind { fallAlert, caregiverRevoked, ignored }

/// Push `type` values sent by the backend (`FcmPushGateway`).
const fallAlertPushType = 'fall_alert';
const caregiverRevokedPushType = 'caregiver_revoked';

/// Allowlist-based classification of FCM `data` payloads.
///
/// Only known types are acted on. Messages without `type` are accepted as
/// fall alerts only when they carry the fall alert keys (`alertId` and
/// `fallTimestamp`), which is the shape older backends sent. Anything else is
/// ignored so an unexpected payload can never open the emergency screen.
PushKind classifyPush(Map<String, dynamic> data) {
  final type = data['type'];
  if (type == caregiverRevokedPushType) return PushKind.caregiverRevoked;
  if (type == fallAlertPushType) {
    return PendingAlertStore.looksLikeFallAlert(data)
        ? PushKind.fallAlert
        : PushKind.ignored;
  }
  if (type == null && PendingAlertStore.looksLikeFallAlert(data)) {
    return PushKind.fallAlert;
  }
  return PushKind.ignored;
}

/// Work done for a push received while the app is in background/terminated.
///
/// Persists the alert for the UI and reports receipt to the backend. The
/// receipt needs the device token from the keychain; see
/// `caregiverIOSOptions` for why it is readable while the phone is locked.
Future<void> handleBackgroundPush(
  Map<String, dynamic> data, {
  PendingAlertStore? store,
  CaregiverBackendService? backend,
}) async {
  if (classifyPush(data) != PushKind.fallAlert) {
    // caregiver_revoked in background: link state is refreshed on next resume.
    return;
  }

  await (store ?? PendingAlertStore()).save(data);
  final alertId = data['alertId'] as String;
  try {
    await (backend ?? CaregiverBackendService()).reportAlertReceived(alertId);
  } catch (error, stackTrace) {
    developer.log(
      'Background alert receipt report failed for $alertId',
      name: 'PushNotificationService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Top-level handler required by FCM for background/terminated state.
/// Must be a top-level function (not a class method).
// coverage:ignore-start
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  developer.log(
    'FCM background message: ${message.messageId}',
    name: 'PushNotificationService',
  );
  await handleBackgroundPush(message.data);
}
// coverage:ignore-end

/// Thin seam over `FirebaseMessaging` so routing logic can be unit-tested.
abstract class PushMessagingClient {
  Future<void> registerBackgroundHandler();
  Future<void> requestPermission();
  Stream<Map<String, dynamic>> get onForegroundMessage;
  Stream<Map<String, dynamic>> get onMessageOpenedApp;
  Future<Map<String, dynamic>?> initialMessageData();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
}

// Plugin wrapper: behavior is covered through PushNotificationService tests.
// coverage:ignore-start
class FirebasePushMessagingClient implements PushMessagingClient {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<void> registerBackgroundHandler() async {
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  }

  @override
  Future<void> requestPermission() async {
    // iOS requires an explicit request; Android 13+ also requires it.
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    developer.log(
      'FCM permission: ${settings.authorizationStatus}',
      name: 'PushNotificationService',
    );
  }

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map((message) => message.data);

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);

  @override
  Future<Map<String, dynamic>?> initialMessageData() async =>
      (await _messaging.getInitialMessage())?.data;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
// coverage:ignore-end

class PushNotificationService {
  PushNotificationService({
    required this.onAlertReceived,
    required this.onLinkRevoked,
    PendingAlertStore? pendingAlertStore,
    PushMessagingClient? messaging,
  }) : _pendingAlertStore = pendingAlertStore ?? PendingAlertStore(),
       _messagingOverride = messaging;

  /// Called whenever a fall alert data message arrives (foreground or opened-from-notification).
  final void Function(Map<String, dynamic> data) onAlertReceived;

  /// Called when a caregiver_revoked notification is received in the foreground.
  final void Function() onLinkRevoked;

  final PendingAlertStore _pendingAlertStore;
  final PushMessagingClient? _messagingOverride;
  late final PushMessagingClient _messaging =
      _messagingOverride ?? FirebasePushMessagingClient();

  final List<StreamSubscription<Map<String, dynamic>>> _subscriptions = [];

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  Future<void> initialize() async {
    // Register background handler (must be called before any other Firebase setup)
    await _messaging.registerBackgroundHandler();
    await _messaging.requestPermission();

    _subscriptions
      ..add(_messaging.onForegroundMessage.listen(_route))
      // Opened from notification (background → foreground).
      ..add(_messaging.onMessageOpenedApp.listen(_routeOpened));

    // Launched from terminated state via notification tap.
    final initialData = await _messaging.initialMessageData();
    if (initialData != null && initialData.isNotEmpty) {
      await _routeOpened(initialData);
    }

    // Alerts stored by the background handler while the UI was not alive,
    // for every protected person (oldest first).
    for (final pendingAlert in await _pendingAlertStore.takeAll()) {
      onAlertReceived(pendingAlert);
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _routeOpened(Map<String, dynamic> data) async {
    if (classifyPush(data) == PushKind.fallAlert) {
      // The tapped alert is presented from its payload; drop its stored copy
      // but keep other pending alerts.
      await _pendingAlertStore.remove(data['alertId'] as String);
    }
    _route(data);
  }

  void _route(Map<String, dynamic> data) {
    switch (classifyPush(data)) {
      case PushKind.caregiverRevoked:
        onLinkRevoked();
      case PushKind.fallAlert:
        onAlertReceived(data);
      case PushKind.ignored:
        // Never log the payload: it may contain location data.
        developer.log(
          'Ignoring push with unsupported type: ${data['type']}',
          name: 'PushNotificationService',
        );
    }
  }

  Future<String?> getFcmToken() async {
    return _messaging.getToken();
  }
}
