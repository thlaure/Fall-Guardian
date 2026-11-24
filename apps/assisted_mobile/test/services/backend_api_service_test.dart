import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
import 'package:fall_guardian/services/device_pairing_state.dart';
import 'package:fall_guardian/services/device_registration_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/services/secure_store.dart';

class _FakeStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  late _FakeStore store;

  setUp(() {
    store = _FakeStore();
    // Fresh, empty preferences per test (registration marker lives there).
    SharedPreferences.setMockInitialValues({});
  });

  test('ensureReady registers device once and stores credentials', () async {
    var registerCalls = 0;
    var validationCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/devices/register') {
        registerCalls++;
        return http.Response(
          jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/protected/linked-caregivers') {
        validationCalls++;
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('[]', 200);
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);

    await service.ensureReady();
    await service.ensureReady();

    expect(registerCalls, 1);
    expect(validationCalls, 2);
    expect(store.data['backend_device_id'], 'device-1');
    expect(store.data['backend_device_token'], 'token-1');
  });

  test('ensureReady throws typed exception on validation failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient(
        (request) async => http.Response('backend unavailable', 503),
      ),
    );

    await expectLater(
      service.ensureReady(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', 'backend unavailable'),
      ),
    );
  });

  test('debugBaseUrl exposes the resolved backend URL', () {
    final service = BackendApiService(
      store: store,
      baseUrl: 'https://api.example.test',
    );

    expect(service.debugBaseUrl, 'https://api.example.test');
  });

  test(
    'ensureReady throws when no backend URL is configured in release mode',
    () async {
      final service = BackendApiService(
        store: store,
        releaseMode: true,
        client: MockClient((request) async {
          fail('No backend URL must be rejected before an HTTP request.');
        }),
      );

      await expectLater(service.ensureReady(), throwsA(isA<StateError>()));
    },
  );

  test(
    'ensureReady throws when no backend URL is configured on iOS dev builds',
    () async {
      final service = BackendApiService(
        store: store,
        isIOSPlatform: true,
        client: MockClient((request) async {
          fail('No backend URL must be rejected before an HTTP request.');
        }),
      );

      await expectLater(service.ensureReady(), throwsA(isA<StateError>()));
    },
  );

  test('syncContacts ensures device credentials are registered', () async {
    var registerCalls = 0;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/devices/register');
      registerCalls++;
      return http.Response(
        jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
        201,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = BackendApiService(store: store, client: client);
    await service.syncContacts(const [
      Contact(id: '1', name: 'Alice', phone: '+33600000001'),
    ]);

    expect(registerCalls, 1);
    expect(store.data['backend_device_id'], 'device-1');
  });

  test('ensureReady rejects insecure backend URL in release mode', () async {
    final service = BackendApiService(
      store: store,
      baseUrl: 'http://api.example.test',
      releaseMode: true,
      client: MockClient((request) async {
        fail('Release configuration must be rejected before an HTTP request.');
      }),
    );

    await expectLater(service.ensureReady(), throwsA(isA<StateError>()));
  });

  test('ensureReady accepts an HTTPS backend URL in release mode', () async {
    final service = BackendApiService(
      store: store,
      baseUrl: 'https://api.example.test',
      releaseMode: true,
      client: MockClient((request) async {
        expect(request.url.scheme, 'https');
        if (request.url.path == '/api/v1/protected/linked-caregivers') {
          return http.Response('[]', 200);
        }

        expect(request.url.path, '/api/v1/devices/register');
        return http.Response(
          jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await service.ensureReady();

    expect(store.data['backend_device_token'], 'token-1');
  });

  test('submitFallAlert posts alert without remote contact sync', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/fall-alerts') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['clientAlertId'], 'alert-1');
        expect(payload['locale'], 'en');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response(
          jsonEncode({
            'id': 'server-alert-1',
            'clientAlertId': 'alert-1',
            'status': 'received',
            'fallTimestamp': '2026-04-09T10:00:00+00:00',
            'cancelledAt': null,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);
    await service.submitFallAlert(
      clientAlertId: 'alert-1',
      fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
      locale: 'en',
      latitude: 48.8566,
      longitude: 2.3522,
    );

    expect(requests, [
      'POST /api/v1/devices/register',
      'POST /api/v1/fall-alerts',
    ]);
  });

  test('recordCancelledFallAlert posts cancelled alert audit', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/fall-alerts') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['clientAlertId'], 'cancelled-alert-1');
        expect(payload['locale'], 'fr');
        expect(payload['cancelled'], isTrue);
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response(
          jsonEncode({
            'id': 'server-alert-1',
            'clientAlertId': 'cancelled-alert-1',
            'status': 'cancelled',
            'fallTimestamp': '2026-04-09T10:00:00+00:00',
            'cancelledAt': '2026-04-09T10:00:05+00:00',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);
    await service.recordCancelledFallAlert(
      clientAlertId: 'cancelled-alert-1',
      fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
      locale: 'fr',
      latitude: null,
      longitude: null,
    );

    expect(requests, [
      'POST /api/v1/devices/register',
      'POST /api/v1/fall-alerts',
    ]);
  });

  test(
    'recordCancelledFallAlert throws typed exception on API failure',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';

      final service = BackendApiService(
        store: store,
        client: MockClient(
          (request) async => http.Response('bad request', 400),
        ),
      );

      await expectLater(
        service.recordCancelledFallAlert(
          clientAlertId: 'cancelled-alert-1',
          fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
          locale: 'fr',
          latitude: null,
          longitude: null,
        ),
        throwsA(
          isA<BackendApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.body, 'body', 'bad request'),
        ),
      );
    },
  );

  test('createInvite posts with stored bearer token', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/invites');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode({
          'code': 'ABC12345',
          'expiresAt': '2026-05-16T10:00:00+00:00',
        }),
        201,
      );
    });

    final service = BackendApiService(store: store, client: client);

    final invite = await service.createInvite();

    expect(invite['code'], 'ABC12345');
  });

  test('createInvite throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('server error', 500)),
    );

    await expectLater(
      service.createInvite(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'server error'),
      ),
    );
  });

  test(
    'submitFallAlert throws typed exception on API failure without retrying',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';

      var requestCount = 0;
      final service = BackendApiService(
        store: store,
        // No retry delays configured: a permanent 4xx is not worth retrying,
        // so this must fail on the very first attempt.
        submitRetryDelays: const [],
        client: MockClient((request) async {
          requestCount++;
          return http.Response('bad request', 400);
        }),
      );

      await expectLater(
        service.submitFallAlert(
          clientAlertId: 'alert-1',
          fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
          locale: 'en',
          latitude: null,
          longitude: null,
        ),
        throwsA(
          isA<BackendApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.body, 'body', 'bad request'),
        ),
      );
      expect(requestCount, 1);
    },
  );

  test('submitFallAlert throws typed exception when backend hangs', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      requestTimeout: const Duration(milliseconds: 1),
      submitRetryDelays: const [],
      client: MockClient((request) => Completer<http.Response>().future),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
      ),
      throwsA(
        isA<BackendApiException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test(
    'submitFallAlert retries on a timeout and succeeds on the next attempt',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';

      var requestCount = 0;
      final service = BackendApiService(
        store: store,
        submitRetryDelays: const [Duration.zero],
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 1) {
            // Simulate the phone being locked/unreachable for the very first
            // attempt (e.g. a transient network blip right at fall detection).
            throw const SocketException('unreachable');
          }
          return http.Response('', 201);
        }),
      );

      await service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
      );

      expect(requestCount, 2);
    },
  );

  test('submitFallAlert retries on a 5xx response', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    var requestCount = 0;
    final service = BackendApiService(
      store: store,
      submitRetryDelays: const [Duration.zero],
      client: MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('server error', 500);
        }
        return http.Response('', 201);
      }),
    );

    await service.submitFallAlert(
      clientAlertId: 'alert-1',
      fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
      locale: 'en',
      latitude: null,
      longitude: null,
    );

    expect(requestCount, 2);
  });

  test('submitFallAlert gives up after exhausting all retries', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    var requestCount = 0;
    final service = BackendApiService(
      store: store,
      submitRetryDelays: const [Duration.zero, Duration.zero],
      client: MockClient((request) async {
        requestCount++;
        return http.Response('server error', 500);
      }),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
      ),
      throwsA(isA<BackendApiException>()),
    );
    expect(requestCount, 3);
  });

  test(
    'cancelFallAlert requires the backend to confirm cancelled status',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';

      final service = BackendApiService(
        store: store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/fall-alerts/alert-1/cancel');
          expect(request.headers['authorization'], 'Bearer token-1');
          return http.Response(jsonEncode({'status': 'cancelled'}), 201);
        }),
      );

      await service.cancelFallAlert(clientAlertId: 'alert-1');
    },
  );

  test('cancelFallAlert does not treat a missing alert as confirmed', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      cancellationRetryDelays: const [],
      client: MockClient((request) async => http.Response('missing', 404)),
    );

    await expectLater(
      service.cancelFallAlert(clientAlertId: 'alert-1'),
      throwsA(
        isA<BackendApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test(
    'cancelFallAlert retries an ambiguous failure and confirms cancellation',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';
      var requestCount = 0;

      final service = BackendApiService(
        store: store,
        cancellationRetryDelays: const [Duration.zero],
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 1) {
            return http.Response('temporary failure', 503);
          }
          return http.Response(jsonEncode({'status': 'cancelled'}), 201);
        }),
      );

      await service.cancelFallAlert(clientAlertId: 'alert-1');
      expect(requestCount, 2);
    },
  );

  test('cancelFallAlert throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      cancellationRetryDelays: const [],
      client: MockClient((request) async => http.Response('server error', 500)),
    );

    await expectLater(
      service.cancelFallAlert(clientAlertId: 'alert-1'),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'server error'),
      ),
    );
  });

  test('attachLocation skips API call when no token is stored', () async {
    var called = false;
    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        called = true;
        return http.Response('', 200);
      }),
    );

    await service.attachLocation(
      clientAlertId: 'alert-1',
      latitude: 48.8566,
      longitude: 2.3522,
    );

    expect(called, isFalse);
  });

  test('attachLocation posts the coordinates for an existing alert', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/fall-alerts/alert-1/location');
        expect(request.headers['authorization'], 'Bearer token-1');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['latitude'], 48.8566);
        expect(payload['longitude'], 2.3522);
        return http.Response('', 200);
      }),
    );

    await service.attachLocation(
      clientAlertId: 'alert-1',
      latitude: 48.8566,
      longitude: 2.3522,
    );
  });

  test('attachLocation ignores an already missing/finished alert', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('missing', 404)),
    );

    await service.attachLocation(
      clientAlertId: 'alert-1',
      latitude: 48.8566,
      longitude: 2.3522,
    );
  });

  test('attachLocation throws typed exception on API failure', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('server error', 500)),
    );

    await expectLater(
      service.attachLocation(
        clientAlertId: 'alert-1',
        latitude: 48.8566,
        longitude: 2.3522,
      ),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'server error'),
      ),
    );
  });

  test('getLinkedCaregivers returns parsed list', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/protected/linked-caregivers');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response(
          jsonEncode([
            {'linkedAt': '2025-01-15T10:00:00+00:00', 'platform': 'android'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.getLinkedCaregivers();

    expect(result, hasLength(1));
    expect(result.first['platform'], 'android');
    expect(result.first['linkedAt'], '2025-01-15T10:00:00+00:00');
  });

  test('getLinkedCaregivers keeps named caregivers visible first', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'linkedAt': '2025-01-15T10:00:00+00:00',
              'platform': 'android',
              'caregiverName': null,
            },
            {
              'linkedAt': '2025-01-10T10:00:00+00:00',
              'platform': 'ios',
              'caregiverName': 'Marie',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.getLinkedCaregivers();

    expect(result.first['caregiverName'], 'Marie');
    expect(result.last['caregiverName'], isNull);
  });

  test('getLinkedCaregivers keeps named caregivers first regardless of input order', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'linkedAt': '2025-01-10T10:00:00+00:00',
              'platform': 'ios',
              'caregiverName': 'Marie',
            },
            {
              'linkedAt': '2025-01-15T10:00:00+00:00',
              'platform': 'android',
              'caregiverName': null,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.getLinkedCaregivers();

    expect(result.first['caregiverName'], 'Marie');
    expect(result.last['caregiverName'], isNull);
  });

  test(
    'getLinkedCaregivers orders same-name caregivers by most recent link first',
    () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';

      final service = BackendApiService(
        store: store,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([
              {
                'linkedAt': '2025-01-10T10:00:00+00:00',
                'platform': 'android',
                'caregiverName': 'Older',
              },
              {
                'linkedAt': '2025-01-15T10:00:00+00:00',
                'platform': 'ios',
                'caregiverName': 'Newer',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await service.getLinkedCaregivers();

      expect(result.first['caregiverName'], 'Newer');
      expect(result.last['caregiverName'], 'Older');
    },
  );

  test('getLinkedCaregivers throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('server error', 500)),
    );

    await expectLater(
      service.getLinkedCaregivers(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'server error'),
      ),
    );
  });

  test('BackendApiException.toString includes message, status, and body', () {
    final error = BackendApiException(
      'Failed to fetch',
      statusCode: 503,
      body: 'unavailable',
    );

    expect(
      error.toString(),
      'BackendApiException(Failed to fetch, 503, unavailable)',
    );
  });
  group('re-pairing required instead of silent re-registration', () {
    late DevicePairingState pairing;

    setUp(() {
      pairing = DevicePairingState();
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';
    });

    for (final status in [401]) {
      test(
        'ensureReady on $status flags re-pairing and never registers',
        () async {
          final requests = <String>[];
          final service = BackendApiService(
            store: store,
            pairingState: pairing,
            client: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              return http.Response('rejected', status);
            }),
          );

          await expectLater(
            service.ensureReady(),
            throwsA(
              isA<DeviceRepairRequiredException>().having(
                (error) => error.statusCode,
                'statusCode',
                status,
              ),
            ),
          );

          expect(requests, ['GET /api/v1/protected/linked-caregivers']);
          expect(store.data['backend_device_token'], 'token-1');
          expect(store.data[BackendApiService.reauthRequiredKey], 'true');
          expect(pairing.repairRequired.value, isTrue);
        },
      );
    }

    test(
      'submitFallAlert on 401 fails fast without retry or registration',
      () async {
        final requests = <String>[];
        final service = BackendApiService(
          store: store,
          pairingState: pairing,
          submitRetryDelays: const [Duration.zero, Duration.zero],
          client: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            return http.Response('unauthorized', 401);
          }),
        );

        await expectLater(
          service.submitFallAlert(
            clientAlertId: 'alert-1',
            fallTimestamp: 0,
            locale: 'en',
            latitude: null,
            longitude: null,
          ),
          throwsA(isA<DeviceRepairRequiredException>()),
        );

        expect(requests, ['POST /api/v1/fall-alerts']);
        expect(pairing.repairRequired.value, isTrue);
      },
    );

    test('every authenticated call enters the re-pair state on 401', () async {
      final service = BackendApiService(
        store: store,
        pairingState: pairing,
        cancellationRetryDelays: const [],
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/devices/register') {
            fail('must never register silently');
          }
          return http.Response('unauthorized', 401);
        }),
      );
      final calls = <Future<Object?> Function()>[
        () => service.createInvite(),
        () => service.getLinkedCaregivers(),
        () => service.cancelFallAlert(clientAlertId: 'alert-1'),
        () => service.recordCancelledFallAlert(
          clientAlertId: 'alert-1',
          fallTimestamp: 0,
          locale: 'en',
          latitude: null,
          longitude: null,
        ),
        () => service.attachLocation(
          clientAlertId: 'alert-1',
          latitude: 1,
          longitude: 2,
        ),
      ];

      for (final call in calls) {
        await expectLater(
          call(),
          throwsA(isA<DeviceRepairRequiredException>()),
        );
      }
    });

    test('lost credentials after a rejection never auto-register', () async {
      store.data.clear();
      store.data[BackendApiService.reauthRequiredKey] = 'true';
      final service = BackendApiService(
        store: store,
        pairingState: pairing,
        client: MockClient((request) async => fail('no request expected')),
      );

      await expectLater(
        service.syncContacts(const []),
        throwsA(isA<DeviceRepairRequiredException>()),
      );
      expect(store.data.containsKey('backend_device_id'), isFalse);
      expect(pairing.repairRequired.value, isTrue);
    });

    test(
      'isRepairRequired mirrors the persisted flag (also set natively)',
      () async {
        final service = BackendApiService(store: store, pairingState: pairing);

        expect(await service.isRepairRequired(), isFalse);
        store.data[BackendApiService.reauthRequiredKey] = 'true';
        expect(await service.isRepairRequired(), isTrue);
        expect(pairing.repairRequired.value, isTrue);
      },
    );

    test('ensureReady success clears a stale re-pair flag', () async {
      store.data[BackendApiService.reauthRequiredKey] = 'true';
      pairing.repairRequired.value = true;
      final service = BackendApiService(
        store: store,
        pairingState: pairing,
        client: MockClient((request) async => http.Response('[]', 200)),
      );

      await service.ensureReady();

      expect(
        store.data.containsKey(BackendApiService.reauthRequiredKey),
        isFalse,
      );
      expect(pairing.repairRequired.value, isFalse);
    });

    test(
      'repairDevice explicitly registers anew and clears the flag',
      () async {
        store.data[BackendApiService.reauthRequiredKey] = 'true';
        pairing.repairRequired.value = true;
        final requests = <String>[];
        final service = BackendApiService(
          discardQueuedAlertsForRepair: () async {},
          store: store,
          pairingState: pairing,
          client: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            return http.Response(
              jsonEncode({'deviceId': 'device-2', 'deviceToken': 'token-2'}),
              201,
            );
          }),
        );

        await service.repairDevice();

        expect(requests, ['POST /api/v1/devices/register']);
        expect(store.data['backend_device_id'], 'device-2');
        expect(store.data['backend_device_token'], 'token-2');
        expect(
          store.data.containsKey(BackendApiService.reauthRequiredKey),
          isFalse,
        );
        expect(pairing.repairRequired.value, isFalse);
      },
    );

    test('a failed repairDevice keeps the re-pair state', () async {
      store.data[BackendApiService.reauthRequiredKey] = 'true';
      final service = BackendApiService(
        discardQueuedAlertsForRepair: () async {},
        store: store,
        pairingState: pairing,
        client: MockClient((request) async => http.Response('down', 503)),
      );

      await expectLater(
        service.repairDevice(),
        throwsA(isA<BackendApiException>()),
      );
      expect(store.data[BackendApiService.reauthRequiredKey], 'true');
    });
  });

  group('server deadline receipt', () {
    http.Response response(
      Map<String, Object?> body, {
      Map<String, String> headers = const {},
    }) => http.Response(jsonEncode(body), 201, headers: headers);

    test('fresh alert: remaining = cancelDeadlineAt - receivedAt - round trip', () {
      final receipt = BackendApiService.fallAlertReceiptFrom(
        response(
          {
            'receivedAt': '2026-04-09T10:00:00.500+00:00',
            'cancelDeadlineAt': '2026-04-09T10:00:30.500+00:00',
          },
          headers: {
            // Second-precision Date header earlier than receivedAt is ignored.
            'date': 'Thu, 09 Apr 2026 10:00:00 GMT',
          },
        ),
        roundTrip: const Duration(milliseconds: 400),
      );

      expect(receipt?.remainingGrace, const Duration(milliseconds: 29600));
    });

    test('replayed older alert uses the HTTP Date header as server now', () {
      final receipt = BackendApiService.fallAlertReceiptFrom(
        response(
          {
            'receivedAt': '2026-04-09T10:00:00+00:00',
            'cancelDeadlineAt': '2026-04-09T10:00:30+00:00',
          },
          headers: {'date': 'Thu, 09 Apr 2026 10:00:20 GMT'},
        ),
        roundTrip: Duration.zero,
      );

      expect(receipt?.remainingGrace, const Duration(seconds: 10));
    });

    test('server times are used as-is, so phone clock skew is irrelevant', () {
      // Server clock in 2030 while the phone thinks it is 2026: the result
      // only depends on server-side timestamps.
      final receipt = BackendApiService.fallAlertReceiptFrom(
        response({
          'receivedAt': '2030-01-01T00:00:00Z',
          'cancelDeadlineAt': '2030-01-01T00:00:30Z',
        }),
        roundTrip: const Duration(seconds: 1),
      );

      expect(receipt?.remainingGrace, const Duration(seconds: 29));
    });

    test('expired deadline yields zero, never negative', () {
      final receipt = BackendApiService.fallAlertReceiptFrom(
        response(
          {
            'receivedAt': '2026-04-09T10:00:00Z',
            'cancelDeadlineAt': '2026-04-09T10:00:30Z',
          },
          headers: {'date': 'Thu, 09 Apr 2026 10:05:00 GMT'},
        ),
        roundTrip: Duration.zero,
      );

      expect(receipt?.remainingGrace, Duration.zero);
    });

    test('missing deadline data or invalid body yields no receipt', () {
      expect(
        BackendApiService.fallAlertReceiptFrom(
          response({'status': 'received'}),
          roundTrip: Duration.zero,
        ),
        isNull,
      );
      expect(
        BackendApiService.fallAlertReceiptFrom(
          http.Response('not json', 201),
          roundTrip: Duration.zero,
        ),
        isNull,
      );
      expect(
        BackendApiService.fallAlertReceiptFrom(
          http.Response('[]', 201),
          roundTrip: Duration.zero,
        ),
        isNull,
      );
    });

    test('malformed Date header falls back to receivedAt', () {
      final receipt = BackendApiService.fallAlertReceiptFrom(
        response(
          {
            'receivedAt': '2026-04-09T10:00:00Z',
            'cancelDeadlineAt': '2026-04-09T10:00:30Z',
          },
          headers: {'date': 'yesterday-ish'},
        ),
        roundTrip: Duration.zero,
      );

      expect(receipt?.remainingGrace, const Duration(seconds: 30));
    });

    test(
      'submitFallAlert returns the receipt from the create response',
      () async {
        store.data['backend_device_id'] = 'device-1';
        store.data['backend_device_token'] = 'token-1';
        final service = BackendApiService(
          store: store,
          client: MockClient(
            (request) async => response({
              'receivedAt': '2026-04-09T10:00:00Z',
              'cancelDeadlineAt': '2026-04-09T10:00:30Z',
            }),
          ),
        );

        final receipt = await service.submitFallAlert(
          clientAlertId: 'alert-1',
          fallTimestamp: 0,
          locale: 'en',
          latitude: null,
          longitude: null,
        );

        expect(receipt, isNotNull);
        expect(receipt!.remainingGrace.inSeconds, inInclusiveRange(29, 30));
      },
    );
  });

  test('submitFallAlert retries rate limiting (429)', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';
    var calls = 0;
    final service = BackendApiService(
      store: store,
      submitRetryDelays: const [Duration.zero],
      client: MockClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('slow down', 429)
            : http.Response('{}', 201);
      }),
    );

    await service.submitFallAlert(
      clientAlertId: 'alert-1',
      fallTimestamp: 0,
      locale: 'en',
      latitude: null,
      longitude: null,
    );

    expect(calls, 2);
  });
  group('registration marker (lost credentials)', () {
    const markerKey = SharedPreferencesRegistrationMarker.key;

    Future<bool> markerSet() async =>
        (await SharedPreferences.getInstance()).getBool(markerKey) ?? false;

    test(
      'first launch registers automatically and records the marker',
      () async {
        final service = BackendApiService(
          store: store,
          pairingState: DevicePairingState(),
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/devices/register') {
              return http.Response(
                jsonEncode({'deviceId': 'device-1', 'deviceToken': 'token-1'}),
                201,
              );
            }
            return http.Response('[]', 200);
          }),
        );

        await service.ensureReady();

        expect(store.data['backend_device_token'], 'token-1');
        expect(await markerSet(), isTrue);
      },
    );

    test('credentials lost after a registration require re-pairing instead '
        'of registering an orphan device', () async {
      SharedPreferences.setMockInitialValues({markerKey: true});
      final pairing = DevicePairingState();
      final service = BackendApiService(
        store: store,
        pairingState: pairing,
        client: MockClient((request) async => fail('no request expected')),
      );

      await expectLater(
        service.ensureReady(),
        throwsA(isA<DeviceRepairRequiredException>()),
      );

      expect(store.data.containsKey('backend_device_id'), isFalse);
      expect(store.data[BackendApiService.reauthRequiredKey], 'true');
      expect(pairing.repairRequired.value, isTrue);
    });

    test(
      'existing installs get the marker on the next credential read',
      () async {
        store.data['backend_device_id'] = 'device-1';
        store.data['backend_device_token'] = 'token-1';
        final service = BackendApiService(
          store: store,
          pairingState: DevicePairingState(),
          client: MockClient((request) async => http.Response('[]', 200)),
        );

        expect(await markerSet(), isFalse);
        await service.ensureReady();

        expect(await markerSet(), isTrue);
      },
    );

    test('explicit re-pair works while the marker is set', () async {
      SharedPreferences.setMockInitialValues({markerKey: true});
      store.data[BackendApiService.reauthRequiredKey] = 'true';
      final pairing = DevicePairingState()..repairRequired.value = true;
      final service = BackendApiService(
        discardQueuedAlertsForRepair: () async {},
        store: store,
        pairingState: pairing,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'deviceId': 'device-2', 'deviceToken': 'token-2'}),
            201,
          ),
        ),
      );

      await service.repairDevice();

      expect(store.data['backend_device_token'], 'token-2');
      expect(pairing.repairRequired.value, isFalse);
      expect(await markerSet(), isTrue);
    });

    test('injected marker is honoured', () async {
      final marker = _MemoryMarker()..value = true;
      final service = BackendApiService(
        store: store,
        pairingState: DevicePairingState(),
        registrationMarker: marker,
        client: MockClient((request) async => fail('no request expected')),
      );

      await expectLater(
        service.syncContacts(const []),
        throwsA(isA<DeviceRepairRequiredException>()),
      );
    });
  });
  group('review fixes', () {
    test('403 is a retryable error, never a re-pair trigger', () async {
      store.data['backend_device_id'] = 'device-1';
      store.data['backend_device_token'] = 'token-1';
      final pairing = DevicePairingState();
      var calls = 0;
      final service = BackendApiService(
        store: store,
        pairingState: pairing,
        submitRetryDelays: const [Duration.zero],
        client: MockClient((request) async {
          calls++;
          return calls == 1
              ? http.Response('edge policy', 403)
              : http.Response('{}', 201);
        }),
      );

      await service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: 0,
        locale: 'en',
        latitude: null,
        longitude: null,
      );

      expect(calls, 2);
      expect(pairing.repairRequired.value, isFalse);
      expect(
        store.data.containsKey(BackendApiService.reauthRequiredKey),
        isFalse,
      );
    });

    test(
      'ensureReady on 403 reports a plain failure and keeps credentials',
      () async {
        store.data['backend_device_id'] = 'device-1';
        store.data['backend_device_token'] = 'token-1';
        final pairing = DevicePairingState();
        final service = BackendApiService(
          store: store,
          pairingState: pairing,
          client: MockClient((request) async => http.Response('nope', 403)),
        );

        await expectLater(
          service.ensureReady(),
          throwsA(
            isA<BackendApiException>()
                .having(
                  (e) => e is DeviceRepairRequiredException,
                  'repair',
                  false,
                )
                .having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
        expect(pairing.repairRequired.value, isFalse);
      },
    );

    test('repairDevice reports queued incidents before registering the new '
        'device', () async {
      store.data[BackendApiService.reauthRequiredKey] = 'true';
      final order = <String>[];
      final service = BackendApiService(
        store: store,
        pairingState: DevicePairingState(),
        discardQueuedAlertsForRepair: () async {
          order.add('discard');
          expect(
            store.data.containsKey('backend_device_token'),
            isFalse,
            reason: 'old token gone so the relay cannot send meanwhile',
          );
        },
        client: MockClient((request) async {
          order.add('register');
          return http.Response(
            jsonEncode({'deviceId': 'device-2', 'deviceToken': 'token-2'}),
            201,
          );
        }),
      );

      await service.repairDevice();

      expect(order, ['discard', 'register']);
    });
  });
}

class _MemoryMarker implements DeviceRegistrationMarker {
  bool value = false;

  @override
  Future<bool> isSet() async => value;

  @override
  Future<void> set() async => value = true;
}
