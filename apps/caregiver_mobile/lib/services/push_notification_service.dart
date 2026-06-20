import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

import 'pending_alert_store.dart';

/// Top-level handler required by FCM for background/terminated state.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  developer.log(
    'FCM background message: ${message.messageId}',
    name: 'PushNotificationService',
  );
  if (_isFallAlert(message.data)) {
    await PendingAlertStore().save(message.data);
  }
  // caregiver_revoked in background: _loadLinkState() on next resume handles it.
}

bool _isFallAlert(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  return type == null || type == 'fall_alert';
}

class PushNotificationService {
  PushNotificationService({
    required this.onAlertReceived,
    required this.onLinkRevoked,
    PendingAlertStore? pendingAlertStore,
  }) : _pendingAlertStore = pendingAlertStore ?? PendingAlertStore();

  /// Called whenever a fall alert data message arrives (foreground or opened-from-notification).
  final void Function(Map<String, dynamic> data) onAlertReceived;

  /// Called when a caregiver_revoked notification is received in the foreground.
  final void Function() onLinkRevoked;

  final PendingAlertStore _pendingAlertStore;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Register background handler (must be called before any other Firebase setup)
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // Request permission (iOS requires explicit request; Android 13+ also requires it)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    developer.log(
      'FCM permission: ${settings.authorizationStatus}',
      name: 'PushNotificationService',
    );

    // Foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      developer.log(
        'FCM foreground message: ${message.messageId}',
        name: 'PushNotificationService',
      );
      if (message.data.isNotEmpty) {
        _route(message.data);
      }
    });

    // Opened from notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      developer.log(
        'FCM opened from notification: ${message.messageId}',
        name: 'PushNotificationService',
      );
      if (message.data.isNotEmpty) {
        if (_isFallAlert(message.data)) {
          await _pendingAlertStore.take();
        }
        _route(message.data);
      }
    });

    // Launched from terminated state via notification tap
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null && initialMessage.data.isNotEmpty) {
      if (_isFallAlert(initialMessage.data)) {
        await _pendingAlertStore.take();
      }
      _route(initialMessage.data);
    } else {
      final pendingAlert = await _pendingAlertStore.take();
      if (pendingAlert != null) {
        onAlertReceived(pendingAlert);
      }
    }
  }

  void _route(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'caregiver_revoked') {
      onLinkRevoked();
    } else {
      onAlertReceived(data);
    }
  }

  Future<String?> getFcmToken() async {
    return _messaging.getToken();
  }
}
