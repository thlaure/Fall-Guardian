import 'dart:convert';

import 'package:caregiver_app/main.dart';
import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:caregiver_app/services/caregiver_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_keychain.dart';

void main() {
  const marker = SecureStorageAccessibilityMigration.markerKey;

  late FakeKeychain keychain;
  late List<http.Request> requests;
  late CaregiverBackendService backend;

  setUp(() {
    // Existing caregiver, credentials stored before the keychain fix.
    keychain = FakeKeychain({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
      'caregiver_linked': 'true',
    });
    requests = [];
    backend = CaregiverBackendService(
      baseUrl: 'http://api.test',
      storage: keychain,
      isIOSPlatform: true,
      client: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/api/v1/caregiver/protected-persons' => http.Response(
            jsonEncode([
              {
                'linkId': 'link-1',
                'protectedDeviceId': 'protected-1',
                'protectedDevicePlatform': 'ios',
                'protectedPersonName': 'Marie',
              },
            ]),
            200,
          ),
          '/api/v1/caregiver/alerts' => http.Response('[]', 200),
          _ => http.Response(
            jsonEncode({'deviceId': 'orphan', 'deviceToken': 'orphan'}),
            201,
          ),
        };
      }),
    );
  });

  void moveToBackground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void moveToForeground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'background launch on a locked iPhone holds back migration and registration',
    (tester) async {
      keychain.locked = true;
      moveToBackground(tester);

      await tester.pumpWidget(CaregiverApp(backend: backend));
      await settle(tester);

      // Nothing is migrated, marked done, or registered while locked.
      expect(keychain.items.containsKey(marker), isFalse);
      expect(keychain.accessibilityOf('caregiver_device_token'), 'unlocked');
      expect(
        requests.where((r) => r.url.path == '/api/v1/devices/register'),
        isEmpty,
      );
      expect(keychain.items['caregiver_device_token']?.$1, 'token-1');

      // The user unlocks and opens the app: migration and link refresh run.
      keychain.locked = false;
      moveToForeground(tester);
      await settle(tester);

      expect(keychain.items[marker]?.$1, '1');
      expect(
        keychain.accessibilityOf('caregiver_device_token'),
        'first_unlock_this_device',
      );
      expect(
        requests.map((r) => r.url.path),
        contains('/api/v1/caregiver/protected-persons'),
      );
      expect(
        requests.where((r) => r.url.path == '/api/v1/devices/register'),
        isEmpty,
      );
      expect(
        requests.every(
          (r) =>
              r.headers['Authorization'] == null ||
              r.headers['Authorization'] == 'Bearer token-1',
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('foreground launch migrates before using credentials', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(CaregiverApp(backend: backend));
    await settle(tester);

    expect(keychain.items[marker]?.$1, '1');
    expect(
      keychain.accessibilityOf('caregiver_device_id'),
      'first_unlock_this_device',
    );
    expect(
      requests.where((r) => r.url.path == '/api/v1/devices/register'),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox());
  });

  group('open emergency screen stays current while polling', () {
    late List<Map<String, dynamic>> serverAlerts;

    Map<String, dynamic> alert(String id, String name, {String? status}) => {
      'id': id,
      'status': status ?? 'sent',
      'fallDetectedAt': '2026-05-16T09:00:00+00:00',
      'acknowledged': false,
      'protectedDeviceId': 'device-$id',
      'protectedDevicePlatform': 'ios',
      'protectedPersonName': name,
    };

    setUp(() {
      serverAlerts = [];
      keychain = FakeKeychain({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
        SecureStorageAccessibilityMigration.markerKey: '1',
      });
      backend = CaregiverBackendService(
        baseUrl: 'http://api.test',
        storage: keychain,
        isIOSPlatform: true,
        client: MockClient((request) async {
          return switch (request.url.path) {
            '/api/v1/caregiver/alerts' => http.Response(
              jsonEncode(serverAlerts),
              200,
            ),
            '/api/v1/caregiver/protected-persons' => http.Response('[]', 200),
            _ => http.Response('{}', 202),
          };
        }),
      );
    });

    Future<void> poll(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
    }

    testWidgets('shows when another caregiver acknowledges the open alert', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      serverAlerts = [alert('alert-1', 'Marie')];

      await tester.pumpWidget(CaregiverApp(backend: backend));
      await settle(tester);
      expect(find.text('Marie may have fallen'), findsOneWidget);
      expect(find.textContaining('Another caregiver'), findsNothing);

      // Current API: the status flips to `acknowledged` for everyone.
      serverAlerts = [alert('alert-1', 'Marie', status: 'acknowledged')];
      await poll(tester);

      expect(find.text('Marie may have fallen'), findsOneWidget);
      expect(find.text('Another caregiver is handling this'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('counts an alert queued while the screen is open', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      serverAlerts = [alert('alert-1', 'Marie')];

      await tester.pumpWidget(CaregiverApp(backend: backend));
      await settle(tester);
      expect(find.textContaining('more alert'), findsNothing);

      serverAlerts = [...serverAlerts, alert('alert-2', 'Paul')];
      await poll(tester);

      await tester.scrollUntilVisible(find.text('1 more alert waiting'), 100);
      expect(find.text('1 more alert waiting'), findsOneWidget);
      expect(find.text('Marie may have fallen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
