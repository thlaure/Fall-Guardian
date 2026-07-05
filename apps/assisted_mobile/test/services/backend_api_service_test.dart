import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/services/backend_api_service.dart';
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
  });

  test('ensureReady registers device once and stores credentials', () async {
    var registerCalls = 0;
    var validationCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/devices/register') {
        registerCalls++;
        return http.Response(
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
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

  test('ensureReady refreshes stale stored credentials after unauthorized',
      () async {
    store.data['backend_device_id'] = 'stale-device';
    store.data['backend_device_token'] = 'stale-token';

    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/protected/linked-caregivers' &&
          request.headers['authorization'] == 'Bearer stale-token') {
        return http.Response('unauthorized', 401);
      }

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({
            'deviceId': 'fresh-device',
            'deviceToken': 'fresh-token',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/protected/linked-caregivers' &&
          request.headers['authorization'] == 'Bearer fresh-token') {
        return http.Response('[]', 200);
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);

    await service.ensureReady();

    expect(store.data['backend_device_id'], 'fresh-device');
    expect(store.data['backend_device_token'], 'fresh-token');
    expect(requests, [
      'GET /api/v1/protected/linked-caregivers',
      'POST /api/v1/devices/register',
      'GET /api/v1/protected/linked-caregivers',
    ]);
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

  test('ensureReady throws when refreshed credentials cannot be validated',
      () async {
    store.data['backend_device_id'] = 'stale-device';
    store.data['backend_device_token'] = 'stale-token';

    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/protected/linked-caregivers' &&
          request.headers['authorization'] == 'Bearer stale-token') {
        return http.Response('unauthorized', 401);
      }

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({
            'deviceId': 'fresh-device',
            'deviceToken': 'fresh-token',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/protected/linked-caregivers' &&
          request.headers['authorization'] == 'Bearer fresh-token') {
        return http.Response('still unavailable', 503);
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);

    await expectLater(
      service.ensureReady(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', 'still unavailable'),
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

    await expectLater(
      service.ensureReady(),
      throwsA(isA<StateError>()),
    );
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
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
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
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
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
      contacts: const [
        Contact(id: '1', name: 'Alice', phone: '+33600000001'),
        Contact(id: '2', name: 'Bob', phone: '+33600000002'),
      ],
    );

    expect(requests, [
      'POST /api/v1/devices/register',
      'POST /api/v1/fall-alerts',
    ]);
  });

  test('submitFallAlert refreshes stale credentials after unauthorized',
      () async {
    store.data['backend_device_id'] = 'stale-device';
    store.data['backend_device_token'] = 'stale-token';

    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/fall-alerts' &&
          request.headers['authorization'] == 'Bearer stale-token') {
        return http.Response('unauthorized', 401);
      }

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({
            'deviceId': 'fresh-device',
            'deviceToken': 'fresh-token',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/fall-alerts' &&
          request.headers['authorization'] == 'Bearer fresh-token') {
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
      latitude: null,
      longitude: null,
      contacts: const [],
    );

    expect(store.data['backend_device_id'], 'fresh-device');
    expect(store.data['backend_device_token'], 'fresh-token');
    expect(requests, [
      'POST /api/v1/fall-alerts',
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
          jsonEncode({
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
          }),
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
      'recordCancelledFallAlert refreshes stale credentials after unauthorized',
      () async {
    store.data['backend_device_id'] = 'stale-device';
    store.data['backend_device_token'] = 'stale-token';

    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/fall-alerts' &&
          request.headers['authorization'] == 'Bearer stale-token') {
        return http.Response('unauthorized', 401);
      }

      if (request.url.path == '/api/v1/devices/register') {
        return http.Response(
          jsonEncode({
            'deviceId': 'fresh-device',
            'deviceToken': 'fresh-token',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/fall-alerts' &&
          request.headers['authorization'] == 'Bearer fresh-token') {
        return http.Response('', 201);
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

    expect(store.data['backend_device_id'], 'fresh-device');
    expect(requests, [
      'POST /api/v1/fall-alerts',
      'POST /api/v1/devices/register',
      'POST /api/v1/fall-alerts',
    ]);
  });

  test('recordCancelledFallAlert throws typed exception on API failure',
      () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('bad request', 400)),
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
  });

  test('createInvite posts with stored bearer token', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/invites');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode(
            {'code': 'ABC12345', 'expiresAt': '2026-05-16T10:00:00+00:00'}),
        201,
      );
    });

    final service = BackendApiService(store: store, client: client);

    final invite = await service.createInvite();

    expect(invite['code'], 'ABC12345');
  });

  test('createInvite refreshes stale credentials after unauthorized response',
      () async {
    store.data['backend_device_id'] = 'stale-device';
    store.data['backend_device_token'] = 'stale-token';

    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');

      if (request.url.path == '/api/v1/invites' &&
          request.headers['authorization'] == 'Bearer stale-token') {
        return http.Response('unauthorized', 401);
      }

      if (request.url.path == '/api/v1/devices/register') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['deviceType'], 'protected_person');
        return http.Response(
          jsonEncode({
            'deviceId': 'fresh-device',
            'deviceToken': 'fresh-token',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/invites' &&
          request.headers['authorization'] == 'Bearer fresh-token') {
        return http.Response(
          jsonEncode({
            'code': 'FRESH123',
            'expiresAt': '2026-05-16T10:00:00+00:00',
          }),
          201,
        );
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final service = BackendApiService(store: store, client: client);

    final invite = await service.createInvite();

    expect(invite['code'], 'FRESH123');
    expect(store.data['backend_device_id'], 'fresh-device');
    expect(store.data['backend_device_token'], 'fresh-token');
    expect(requests, [
      'POST /api/v1/invites',
      'POST /api/v1/devices/register',
      'POST /api/v1/invites',
    ]);
  });

  test('createInvite throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('forbidden', 403)),
    );

    await expectLater(
      service.createInvite(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });

  test('submitFallAlert throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('bad request', 400)),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
        contacts: const [],
      ),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.body, 'body', 'bad request'),
      ),
    );
  });

  test('submitFallAlert throws typed exception when backend hangs', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      requestTimeout: const Duration(milliseconds: 1),
      client: MockClient((request) => Completer<http.Response>().future),
    );

    await expectLater(
      service.submitFallAlert(
        clientAlertId: 'alert-1',
        fallTimestamp: DateTime.utc(2026, 4, 9, 10).millisecondsSinceEpoch,
        locale: 'en',
        latitude: null,
        longitude: null,
        contacts: const [],
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

  test('cancelFallAlert skips API call when no token is stored', () async {
    var called = false;
    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        called = true;
        return http.Response('', 204);
      }),
    );

    await service.cancelFallAlert(clientAlertId: 'alert-1');

    expect(called, isFalse);
  });

  test('cancelFallAlert ignores already missing backend alert', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/fall-alerts/alert-1/cancel');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('missing', 404);
      }),
    );

    await service.cancelFallAlert(clientAlertId: 'alert-1');
  });

  test('cancelFallAlert throws typed exception on API failure', () async {
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
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

  test(
    'getLinkedCaregivers keeps named caregivers first regardless of input order',
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
    },
  );

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
      client: MockClient((request) async => http.Response('forbidden', 403)),
    );

    await expectLater(
      service.getLinkedCaregivers(),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.body, 'body', 'forbidden'),
      ),
    );
  });

  test('deleteLinkedCaregiver sends DELETE and succeeds on 204', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';
    const linkId = 'some-link-uuid';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/v1/protected/linked-caregivers/$linkId');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('', 204);
      }),
    );

    await expectLater(service.deleteLinkedCaregiver(linkId), completes);
  });

  test('deleteLinkedCaregiver throws typed exception on API failure', () async {
    store.data['backend_device_id'] = 'device-1';
    store.data['backend_device_token'] = 'token-1';

    final service = BackendApiService(
      store: store,
      client: MockClient((request) async => http.Response('not found', 404)),
    );

    await expectLater(
      service.deleteLinkedCaregiver('missing-id'),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.body, 'body', 'not found'),
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
}
