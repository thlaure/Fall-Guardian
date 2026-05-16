import 'dart:convert';

import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://api.test';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'ensureRegistered registers a caregiver device and stores credentials',
    () async {
      final requests = <http.Request>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add(request);

          return http.Response(
            jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
            201,
          );
        }),
      );

      await service.ensureRegistered();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/devices/register');
      expect(
        jsonDecode(requests.single.body),
        containsPair('deviceType', 'caregiver'),
      );
    },
  );

  test(
    'ensureRegistered throws typed exception on registration failure',
    () async {
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          return http.Response('unavailable', 503);
        }),
      );

      await expectLater(
        service.ensureRegistered(),
        throwsA(
          isA<CaregiverApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.body, 'body', 'unavailable'),
        ),
      );
    },
  );

  test('acceptInvite reuses stored device token as bearer auth', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    late http.Request capturedRequest;
    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 204);
      }),
    );

    await service.acceptInvite('ABC12345');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/v1/invites/ABC12345/accept');
    expect(capturedRequest.headers['Authorization'], 'Bearer token-1');
    expect(await service.isLinked(), isTrue);
  });

  test('getCaregiverAlerts accepts API Platform hydra collection', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'hydra:member': [
              {'id': 'alert-1'},
              {'id': 'alert-2'},
            ],
          }),
          200,
        );
      }),
    );

    final alerts = await service.getCaregiverAlerts();

    expect(alerts, hasLength(2));
    expect(alerts.first['id'], 'alert-1');
  });

  test('getCaregiverAlerts accepts plain JSON array', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'id': 'alert-1'},
          ]),
          200,
        );
      }),
    );

    final alerts = await service.getCaregiverAlerts();

    expect(alerts.single['id'], 'alert-1');
  });

  test('getCaregiverAlerts throws typed exception on API failure', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response('forbidden', 403);
      }),
    );

    await expectLater(
      service.getCaregiverAlerts(),
      throwsA(
        isA<CaregiverApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });

  test(
    'getLatestActiveAlertData returns newest unacknowledged active alert',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'hydra:member': [
                {
                  'id': 'old-alert',
                  'status': 'received',
                  'fallDetectedAt': '2026-05-16T08:00:00+00:00',
                  'latitude': null,
                  'longitude': null,
                  'acknowledged': false,
                },
                {
                  'id': 'cancelled-alert',
                  'status': 'cancelled',
                  'fallDetectedAt': '2026-05-16T10:00:00+00:00',
                  'acknowledged': false,
                },
                {
                  'id': 'new-alert',
                  'status': 'received',
                  'fallDetectedAt': '2026-05-16T09:00:00+00:00',
                  'latitude': 48.8566,
                  'longitude': 2.3522,
                  'acknowledged': false,
                },
              ],
            }),
            200,
          );
        }),
      );

      final alert = await service.getLatestActiveAlertData();

      expect(alert?['alertId'], 'new-alert');
      expect(alert?['fallTimestamp'], '2026-05-16T09:00:00+00:00');
      expect(alert?['latitude'], '48.8566');
      expect(alert?['longitude'], '2.3522');
    },
  );

  test(
    'getLatestActiveAlertData returns null when no active alert exists',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'hydra:member': [
                {
                  'id': 'acknowledged-alert',
                  'status': 'received',
                  'fallDetectedAt': '2026-05-16T08:00:00+00:00',
                  'acknowledged': true,
                },
                {
                  'id': 'cancelled-alert',
                  'status': 'cancelled',
                  'fallDetectedAt': '2026-05-16T09:00:00+00:00',
                  'acknowledged': false,
                },
              ],
            }),
            200,
          );
        }),
      );

      expect(await service.getLatestActiveAlertData(), isNull);
    },
  );

  test('acknowledgeFallAlert posts bearer-authenticated request', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    late http.Request capturedRequest;
    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 204);
      }),
    );

    await service.acknowledgeFallAlert('alert-1');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/v1/fall-alerts/alert-1/acknowledge');
    expect(capturedRequest.headers['Authorization'], 'Bearer token-1');
  });

  test('acknowledgeFallAlert throws typed exception on API failure', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response('forbidden', 403);
      }),
    );

    await expectLater(
      service.acknowledgeFallAlert('alert-1'),
      throwsA(
        isA<CaregiverApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });

  test('registerPushToken posts bearer-authenticated token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    late http.Request capturedRequest;
    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 204);
      }),
    );

    await service.registerPushToken('fcm-token');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/v1/caregiver/push-token');
    expect(capturedRequest.headers['Authorization'], 'Bearer token-1');
    expect(jsonDecode(capturedRequest.body), {'fcmToken': 'fcm-token'});
  });

  test('registerPushToken throws typed exception on API failure', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response('forbidden', 403);
      }),
    );

    await expectLater(
      service.registerPushToken('fcm-token'),
      throwsA(
        isA<CaregiverApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });
}
