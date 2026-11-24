import 'dart:async';

import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:caregiver_app/services/pending_alert_store.dart';
import 'package:caregiver_app/services/push_notification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alert = {
  'type': 'fall_alert',
  'alertId': 'alert-1',
  'fallTimestamp': '2026-05-16T08:30:00+00:00',
};

class _FakeMessaging implements PushMessagingClient {
  final foreground = StreamController<Map<String, dynamic>>.broadcast();
  final opened = StreamController<Map<String, dynamic>>.broadcast();
  final tokens = StreamController<String>.broadcast();
  Map<String, dynamic>? initial;
  bool backgroundRegistered = false;
  bool permissionRequested = false;

  Future<void> close() async {
    await foreground.close();
    await opened.close();
    await tokens.close();
  }

  @override
  Future<void> registerBackgroundHandler() async => backgroundRegistered = true;

  @override
  Future<void> requestPermission() async => permissionRequested = true;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => foreground.stream;

  @override
  Stream<Map<String, dynamic>> get onMessageOpenedApp => opened.stream;

  @override
  Future<Map<String, dynamic>?> initialMessageData() async => initial;

  @override
  Future<String?> getToken() async => 'fcm-token';

  @override
  Stream<String> get onTokenRefresh => tokens.stream;
}

class _RecordingBackend extends CaregiverBackendService {
  _RecordingBackend({this.fail = false});

  final bool fail;
  final List<String> receipts = [];

  @override
  Future<void> reportAlertReceived(String alertId) async {
    if (fail) throw CaregiverApiException('offline');
    receipts.add(alertId);
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('classifyPush', () {
    test('accepts fall alerts sent by the current backend', () {
      expect(classifyPush(_alert), PushKind.fallAlert);
      expect(classifyPush({..._alert, 'reminder': '1'}), PushKind.fallAlert);
    });

    test('accepts legacy messages without type carrying alert keys', () {
      expect(
        classifyPush({
          'alertId': 'alert-1',
          'fallTimestamp': '2026-05-16T08:30:00+00:00',
        }),
        PushKind.fallAlert,
      );
    });

    test('recognizes caregiver revocation', () {
      expect(
        classifyPush({'type': 'caregiver_revoked'}),
        PushKind.caregiverRevoked,
      );
    });

    test('ignores unknown types and incomplete payloads', () {
      expect(classifyPush({}), PushKind.ignored);
      expect(classifyPush({'alertId': 'alert-1'}), PushKind.ignored);
      expect(classifyPush({..._alert, 'type': 'marketing'}), PushKind.ignored);
      expect(classifyPush({'type': 'fall_alert'}), PushKind.ignored);
      expect(classifyPush({..._alert, 'type': 42}), PushKind.ignored);
    });
  });

  group('handleBackgroundPush', () {
    test('stores the alert and reports receipt', () async {
      final store = PendingAlertStore();
      final backend = _RecordingBackend();

      await handleBackgroundPush(_alert, store: store, backend: backend);

      expect(backend.receipts, ['alert-1']);
      expect((await store.takeAll()).single['alertId'], 'alert-1');
    });

    test('keeps the alert when the receipt report fails', () async {
      final store = PendingAlertStore();

      await handleBackgroundPush(
        _alert,
        store: store,
        backend: _RecordingBackend(fail: true),
      );

      expect(await store.takeAll(), hasLength(1));
    });

    test('ignores non-alert pushes', () async {
      final store = PendingAlertStore();
      final backend = _RecordingBackend();

      await handleBackgroundPush(
        {'type': 'caregiver_revoked'},
        store: store,
        backend: backend,
      );
      await handleBackgroundPush(
        {'type': 'other', 'alertId': 'x', 'fallTimestamp': 'y'},
        store: store,
        backend: backend,
      );

      expect(backend.receipts, isEmpty);
      expect(await store.takeAll(), isEmpty);
    });
  });

  group('PushNotificationService', () {
    late _FakeMessaging messaging;
    late PendingAlertStore store;
    late List<Map<String, dynamic>> alerts;
    late int revocations;
    late PushNotificationService service;

    setUp(() {
      messaging = _FakeMessaging();
      store = PendingAlertStore();
      alerts = [];
      revocations = 0;
      service = PushNotificationService(
        onAlertReceived: alerts.add,
        onLinkRevoked: () => revocations++,
        pendingAlertStore: store,
        messaging: messaging,
      );
    });

    tearDown(() async {
      await service.dispose();
      await messaging.close();
    });

    test('registers handlers and routes foreground messages', () async {
      await service.initialize();

      expect(messaging.backgroundRegistered, isTrue);
      expect(messaging.permissionRequested, isTrue);

      messaging.foreground.add(_alert);
      messaging.foreground.add({'type': 'caregiver_revoked'});
      messaging.foreground.add({'type': 'unknown'});
      await pumpEventQueue();

      expect(alerts.map((a) => a['alertId']), ['alert-1']);
      expect(revocations, 1);
    });

    test('presents every pending alert stored while the UI was dead', () async {
      await store.save({..._alert, 'alertId': 'alert-a'});
      await store.save({..._alert, 'alertId': 'alert-b'});

      await service.initialize();

      expect(alerts.map((a) => a['alertId']), ['alert-a', 'alert-b']);
      expect(await store.takeAll(), isEmpty);
    });

    test(
      'launch from a notification presents it and the other pending alerts',
      () async {
        await store.save({..._alert, 'alertId': 'alert-a'});
        await store.save({..._alert, 'alertId': 'alert-b'});
        messaging.initial = {..._alert, 'alertId': 'alert-b'};

        await service.initialize();

        expect(alerts.map((a) => a['alertId']), ['alert-b', 'alert-a']);
      },
    );

    test('opening a notification removes only its stored copy', () async {
      await service.initialize();
      await store.save({..._alert, 'alertId': 'alert-a'});
      await store.save({..._alert, 'alertId': 'alert-b'});

      messaging.opened.add({..._alert, 'alertId': 'alert-b'});
      await pumpEventQueue();

      expect(alerts.map((a) => a['alertId']), ['alert-b']);
      expect((await store.takeAll()).single['alertId'], 'alert-a');
    });

    test('opened revocation notifications refresh link state', () async {
      messaging.initial = {'type': 'caregiver_revoked'};

      await service.initialize();

      expect(revocations, 1);
      expect(alerts, isEmpty);
    });

    test('exposes FCM token and refresh stream', () async {
      expect(await service.getFcmToken(), 'fcm-token');
      final refreshed = service.onTokenRefresh.first;
      messaging.tokens.add('new-token');
      expect(await refreshed, 'new-token');
    });
  });
}
