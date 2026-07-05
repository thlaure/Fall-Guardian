import 'dart:async';
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

  test(
    'ensureRegistered throws when no backend URL is configured in release mode',
    () async {
      final service = CaregiverBackendService(
        releaseMode: true,
        client: MockClient((request) async {
          fail('No backend URL must be rejected before an HTTP request.');
        }),
      );

      await expectLater(service.ensureRegistered(), throwsA(isA<StateError>()));
    },
  );

  test(
    'ensureRegistered throws when no backend URL is configured on iOS dev builds',
    () async {
      final service = CaregiverBackendService(
        isIOSPlatform: true,
        client: MockClient((request) async {
          fail('No backend URL must be rejected before an HTTP request.');
        }),
      );

      await expectLater(service.ensureRegistered(), throwsA(isA<StateError>()));
    },
  );

  test(
    'ensureRegistered rejects insecure backend URL in release mode',
    () async {
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        releaseMode: true,
        client: MockClient((request) async {
          fail(
            'Release configuration must be rejected before an HTTP request.',
          );
        }),
      );

      await expectLater(service.ensureRegistered(), throwsA(isA<StateError>()));
    },
  );

  test(
    'ensureRegistered accepts an HTTPS backend URL in release mode',
    () async {
      final service = CaregiverBackendService(
        baseUrl: 'https://api.example.test',
        releaseMode: true,
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          expect(request.url.path, '/api/v1/devices/register');
          return http.Response(
            jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
            201,
          );
        }),
      );

      await service.ensureRegistered();
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

    const inviteCode = '669CBEC261CDDF65DD21F4D2A2452689';

    await service.acceptInvite(
      inviteCode,
      protectedPersonName: 'Marie',
      caregiverName: 'Thomas',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/v1/invites/$inviteCode/accept');
    expect(capturedRequest.headers['Authorization'], 'Bearer token-1');
    expect(jsonDecode(capturedRequest.body), {
      'protectedPersonName': 'Marie',
      'caregiverName': 'Thomas',
    });
    expect(await service.isLinked(), isTrue);
  });

  test('markUnlinked clears the persisted caregiver link state', () async {
    FlutterSecureStorage.setMockInitialValues({'caregiver_linked': 'true'});

    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        fail('markUnlinked must not call the backend.');
      }),
    );

    await service.markUnlinked();

    expect(await service.isLinked(), isFalse);
  });

  test(
    'refreshLinkedProtectedPersons stores true when at least one link exists',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
        'caregiver_linked': 'false',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/caregiver/protected-persons');
          expect(request.headers['Authorization'], 'Bearer token-1');

          return http.Response(
            jsonEncode({
              'hydra:member': [
                {'protectedDeviceId': 'protected-1'},
              ],
            }),
            200,
          );
        }),
      );

      final linked = await service.refreshLinkedProtectedPersons();

      expect(linked, isTrue);
      expect(await service.isLinked(), isTrue);
    },
  );

  test(
    'getLinkedProtectedPersons returns linked devices from API Platform',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/caregiver/protected-persons');

          return http.Response(
            jsonEncode({
              'hydra:member': [
                {
                  'protectedDeviceId': 'protected-1',
                  'protectedDevicePlatform': 'ios',
                  'protectedPersonName': 'Marie',
                },
                {
                  'protectedDeviceId': 'protected-2',
                  'protectedDevicePlatform': 'android',
                  'protectedPersonName': 'Paul',
                },
              ],
            }),
            200,
          );
        }),
      );

      final protectedPersons = await service.getLinkedProtectedPersons();

      expect(protectedPersons, hasLength(2));
      expect(protectedPersons.first.protectedDeviceId, 'protected-1');
      expect(protectedPersons.first.protectedDevicePlatform, 'ios');
      expect(protectedPersons.first.protectedPersonName, 'Marie');
      expect(protectedPersons.last.protectedDevicePlatform, 'android');
      expect(protectedPersons.last.protectedPersonName, 'Paul');
    },
  );

  test(
    'getLinkedProtectedPersons throws typed exception on API failure',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          return http.Response('unavailable', 503);
        }),
      );

      await expectLater(
        service.getLinkedProtectedPersons(),
        throwsA(
          isA<CaregiverApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.body, 'body', 'unavailable'),
        ),
      );
    },
  );

  test(
    'getLinkedProtectedPersons keeps named protected persons visible first',
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
                  'protectedDeviceId': 'protected-without-name',
                  'protectedDevicePlatform': 'ios',
                  'protectedPersonName': null,
                },
                {
                  'protectedDeviceId': 'protected-with-name',
                  'protectedDevicePlatform': 'android',
                  'protectedPersonName': 'Marie',
                },
              ],
            }),
            200,
          );
        }),
      );

      final protectedPersons = await service.getLinkedProtectedPersons();

      expect(protectedPersons.first.protectedDeviceId, 'protected-with-name');
      expect(protectedPersons.first.protectedPersonName, 'Marie');
      expect(protectedPersons.last.protectedDeviceId, 'protected-without-name');
    },
  );

  test(
    'getLinkedProtectedPersons keeps named protected persons first regardless of input order',
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
                  'protectedDeviceId': 'protected-with-name',
                  'protectedDevicePlatform': 'android',
                  'protectedPersonName': 'Marie',
                },
                {
                  'protectedDeviceId': 'protected-without-name',
                  'protectedDevicePlatform': 'ios',
                  'protectedPersonName': null,
                },
              ],
            }),
            200,
          );
        }),
      );

      final protectedPersons = await service.getLinkedProtectedPersons();

      expect(protectedPersons.first.protectedDeviceId, 'protected-with-name');
      expect(protectedPersons.last.protectedDeviceId, 'protected-without-name');
    },
  );

  test(
    'getLinkedProtectedPersons refreshes stale credentials after unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'stale-device',
        'caregiver_device_token': 'stale-token',
      });

      final requests = <String>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');

          if (request.url.path == '/api/v1/caregiver/protected-persons' &&
              request.headers['Authorization'] == 'Bearer stale-token') {
            return http.Response('unauthorized', 401);
          }

          if (request.url.path == '/api/v1/devices/register') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['deviceType'], 'caregiver');
            return http.Response(
              jsonEncode({
                'deviceId': 'fresh-device',
                'deviceToken': 'fresh-token',
              }),
              201,
            );
          }

          if (request.url.path == '/api/v1/caregiver/protected-persons' &&
              request.headers['Authorization'] == 'Bearer fresh-token') {
            return http.Response(
              jsonEncode({
                'hydra:member': [
                  {'protectedDeviceId': 'protected-1'},
                ],
              }),
              200,
            );
          }

          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final protectedPersons = await service.getLinkedProtectedPersons();

      expect(protectedPersons.single.protectedDeviceId, 'protected-1');
      expect(requests, [
        'GET /api/v1/caregiver/protected-persons',
        'POST /api/v1/devices/register',
        'GET /api/v1/caregiver/protected-persons',
      ]);
    },
  );

  test(
    'refreshLinkedProtectedPersons stores false when no link remains',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
        'caregiver_linked': 'true',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'hydra:member': <Map<String, dynamic>>[]}),
            200,
          );
        }),
      );

      final linked = await service.refreshLinkedProtectedPersons();

      expect(linked, isFalse);
      expect(await service.isLinked(), isFalse);
    },
  );

  test(
    'acceptInvite refreshes stale credentials after unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'stale-device',
        'caregiver_device_token': 'stale-token',
      });

      const inviteCode = '669CBEC261CDDF65DD21F4D2A2452689';
      final requests = <String>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');

          if (request.url.path == '/api/v1/invites/$inviteCode/accept' &&
              request.headers['Authorization'] == 'Bearer stale-token') {
            return http.Response('unauthorized', 401);
          }

          if (request.url.path == '/api/v1/devices/register') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['deviceType'], 'caregiver');
            return http.Response(
              jsonEncode({
                'deviceId': 'fresh-device',
                'deviceToken': 'fresh-token',
              }),
              201,
            );
          }

          if (request.url.path == '/api/v1/invites/$inviteCode/accept' &&
              request.headers['Authorization'] == 'Bearer fresh-token') {
            return http.Response('', 204);
          }

          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      await service.acceptInvite(
        inviteCode,
        protectedPersonName: 'Marie',
        caregiverName: 'Thomas',
      );

      expect(requests, [
        'POST /api/v1/invites/$inviteCode/accept',
        'POST /api/v1/devices/register',
        'POST /api/v1/invites/$inviteCode/accept',
      ]);
      expect(await service.isLinked(), isTrue);
    },
  );

  test('acceptInvite throws typed exception on API failure', () async {
    FlutterSecureStorage.setMockInitialValues({
      'caregiver_device_id': 'device-1',
      'caregiver_device_token': 'token-1',
    });

    const inviteCode = '669CBEC261CDDF65DD21F4D2A2452689';
    final service = CaregiverBackendService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        return http.Response('unavailable', 503);
      }),
    );

    await expectLater(
      service.acceptInvite(
        inviteCode,
        protectedPersonName: 'Marie',
        caregiverName: 'Thomas',
      ),
      throwsA(
        isA<CaregiverApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', 'unavailable'),
      ),
    );
  });

  test(
    'acknowledgeFallAlert refreshes stale credentials after unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'stale-device',
        'caregiver_device_token': 'stale-token',
      });

      final requests = <String>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');

          if (request.url.path == '/api/v1/fall-alerts/alert-1/acknowledge' &&
              request.headers['Authorization'] == 'Bearer stale-token') {
            return http.Response('unauthorized', 401);
          }
          if (request.url.path == '/api/v1/devices/register') {
            return http.Response(
              jsonEncode({
                'deviceId': 'fresh-device',
                'deviceToken': 'fresh-token',
              }),
              201,
            );
          }

          return http.Response('', 204);
        }),
      );

      await service.acknowledgeFallAlert('alert-1');

      expect(requests, [
        'POST /api/v1/fall-alerts/alert-1/acknowledge',
        'POST /api/v1/devices/register',
        'POST /api/v1/fall-alerts/alert-1/acknowledge',
      ]);
    },
  );

  test(
    'registerPushToken refreshes stale credentials after unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'stale-device',
        'caregiver_device_token': 'stale-token',
      });

      final requests = <String>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');

          if (request.url.path == '/api/v1/caregiver/push-token' &&
              request.headers['Authorization'] == 'Bearer stale-token') {
            return http.Response('unauthorized', 401);
          }
          if (request.url.path == '/api/v1/devices/register') {
            return http.Response(
              jsonEncode({
                'deviceId': 'fresh-device',
                'deviceToken': 'fresh-token',
              }),
              201,
            );
          }

          return http.Response('', 204);
        }),
      );

      await service.registerPushToken('fcm-token');

      expect(requests, [
        'POST /api/v1/caregiver/push-token',
        'POST /api/v1/devices/register',
        'POST /api/v1/caregiver/push-token',
      ]);
    },
  );

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

  test(
    'getCaregiverAlerts refreshes stale credentials after unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'stale-device',
        'caregiver_device_token': 'stale-token',
      });

      final requests = <String>[];
      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');

          if (request.url.path == '/api/v1/caregiver/alerts' &&
              request.headers['Authorization'] == 'Bearer stale-token') {
            return http.Response('unauthorized', 401);
          }
          if (request.url.path == '/api/v1/devices/register') {
            return http.Response(
              jsonEncode({
                'deviceId': 'fresh-device',
                'deviceToken': 'fresh-token',
              }),
              201,
            );
          }

          return http.Response(
            jsonEncode({
              'hydra:member': [
                {'id': 'alert-1'},
              ],
            }),
            200,
          );
        }),
      );

      final alerts = await service.getCaregiverAlerts();

      expect(alerts.single['id'], 'alert-1');
      expect(requests, [
        'GET /api/v1/caregiver/alerts',
        'POST /api/v1/devices/register',
        'GET /api/v1/caregiver/alerts',
      ]);
    },
  );

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
    'getCaregiverAlerts throws typed exception when backend hangs',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'caregiver_device_id': 'device-1',
        'caregiver_device_token': 'token-1',
      });

      final service = CaregiverBackendService(
        baseUrl: baseUrl,
        requestTimeout: const Duration(milliseconds: 1),
        client: MockClient((request) => Completer<http.Response>().future),
      );

      await expectLater(
        service.getCaregiverAlerts(),
        throwsA(
          isA<CaregiverApiException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    },
  );

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
    'getLatestActiveAlertData treats an alert with an unparsable date as oldest',
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
                  'id': 'dated-alert',
                  'status': 'received',
                  'fallDetectedAt': '2026-05-16T09:00:00+00:00',
                  'acknowledged': false,
                },
                {
                  'id': 'undated-alert',
                  'status': 'received',
                  'fallDetectedAt': 'not-a-date',
                  'acknowledged': false,
                },
              ],
            }),
            200,
          );
        }),
      );

      final alert = await service.getLatestActiveAlertData();

      expect(alert?['alertId'], 'dated-alert');
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

  test('CaregiverApiException.toString includes message, status, and body', () {
    final error = CaregiverApiException(
      'Failed to fetch',
      statusCode: 503,
      body: 'unavailable',
    );

    expect(
      error.toString(),
      'CaregiverApiException(Failed to fetch, 503, unavailable)',
    );
  });
}
