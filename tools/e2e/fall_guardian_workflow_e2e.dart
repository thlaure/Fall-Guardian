import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  final config = _Config.fromArgs(args);
  final client = _ApiClient(config.baseUrl);
  final runId = _randomRunId();

  await _step('Backend health is reachable', () async {
    final health = await client.get('/health');
    _expectStatus(health, HttpStatus.ok);
  });

  late _Device protectedDevice;
  await _step('Assisted app registers a protected-person device', () async {
    protectedDevice = await client.registerDevice(
      platform: 'ios',
      deviceType: 'protected_person',
      appVersion: 'e2e-$runId',
    );
  });

  late _Device caregiverDevice;
  await _step('Caregiver app registers a caregiver device', () async {
    caregiverDevice = await client.registerDevice(
      platform: 'android',
      deviceType: 'caregiver',
      appVersion: 'e2e-$runId',
    );
  });

  late _Device secondCaregiverDevice;
  await _step(
    'Second caregiver app registers another caregiver device',
    () async {
      secondCaregiverDevice = await client.registerDevice(
        platform: 'android',
        deviceType: 'caregiver',
        appVersion: 'e2e-$runId',
      );
    },
  );

  late String inviteCode;
  await _step('Assisted app creates a caregiver invite', () async {
    final response = await client.post(
      '/api/v1/invites',
      token: protectedDevice.token,
    );
    _expectStatus(response, HttpStatus.created);
    inviteCode = _stringField(response.json, 'code');
  });

  await _step('Caregiver app accepts the invite', () async {
    final response = await client.post(
      '/api/v1/invites/$inviteCode/accept',
      token: caregiverDevice.token,
    );
    _expectStatus(response, HttpStatus.noContent);
  });

  late String secondInviteCode;
  await _step('Assisted app creates a second caregiver invite', () async {
    final response = await client.post(
      '/api/v1/invites',
      token: protectedDevice.token,
    );
    _expectStatus(response, HttpStatus.created);
    secondInviteCode = _stringField(response.json, 'code');
  });

  await _step('Second caregiver app accepts the invite', () async {
    final response = await client.post(
      '/api/v1/invites/$secondInviteCode/accept',
      token: secondCaregiverDevice.token,
    );
    _expectStatus(response, HttpStatus.noContent);
  });

  await _step('Caregiver app sees the linked protected person', () async {
    final response = await client.get(
      '/api/v1/caregiver/protected-persons',
      token: caregiverDevice.token,
    );
    _expectStatus(response, HttpStatus.ok);
    final protectedPersons = _collection(response.json);
    _expect(
      protectedPersons.any(
        (person) => person['protectedDeviceId'] == protectedDevice.id,
      ),
      'Expected caregiver protected-person list to include ${protectedDevice.id}.',
    );
  });

  await _step(
    'Second caregiver app sees the same linked protected person',
    () async {
      final response = await client.get(
        '/api/v1/caregiver/protected-persons',
        token: secondCaregiverDevice.token,
      );
      _expectStatus(response, HttpStatus.ok);
      final protectedPersons = _collection(response.json);
      _expect(
        protectedPersons.any(
          (person) => person['protectedDeviceId'] == protectedDevice.id,
        ),
        'Expected second caregiver protected-person list to include ${protectedDevice.id}.',
      );
    },
  );

  late String activeAlertId;
  final activeClientAlertId = 'e2e-active-$runId';
  await _step('Assisted app submits a fall alert', () async {
    final response = await client.post(
      '/api/v1/fall-alerts',
      token: protectedDevice.token,
      body: {
        'clientAlertId': activeClientAlertId,
        'fallTimestamp': DateTime.now().toUtc().toIso8601String(),
        'locale': 'fr_FR',
        'latitude': 48.8566,
        'longitude': 2.3522,
      },
    );
    _expectStatus(response, HttpStatus.created);
    activeAlertId = _stringField(response.json, 'id');
  });

  await _step('Caregiver app receives the active fall alert', () async {
    final alert = await _pollAlert(
      client: client,
      caregiverToken: caregiverDevice.token,
      alertId: activeAlertId,
    );
    _expect(
      _isVisibleActiveStatus(alert['status']),
      'Expected active alert to remain visible to the caregiver.',
    );
    _expect(
      alert['acknowledged'] == false,
      'Expected active alert to be unacknowledged.',
    );
    _expect(
      alert['latitude'] == 48.8566,
      'Expected active alert latitude to match.',
    );
    _expect(
      alert['longitude'] == 2.3522,
      'Expected active alert longitude to match.',
    );
  });

  await _step(
    'Second caregiver app receives the same active fall alert',
    () async {
      final alert = await _pollAlert(
        client: client,
        caregiverToken: secondCaregiverDevice.token,
        alertId: activeAlertId,
      );
      _expect(
        _isVisibleActiveStatus(alert['status']),
        'Expected second caregiver to receive the active alert in history.',
      );
      _expect(
        alert['acknowledged'] == false,
        'Expected second caregiver alert to start unacknowledged.',
      );
    },
  );

  await _step('Caregiver app acknowledges the fall alert', () async {
    final response = await client.post(
      '/api/v1/fall-alerts/$activeAlertId/acknowledge',
      token: caregiverDevice.token,
    );
    _expectStatus(response, HttpStatus.noContent);
  });

  await _step('Caregiver app sees the alert as acknowledged', () async {
    final alert = await _pollAlert(
      client: client,
      caregiverToken: caregiverDevice.token,
      alertId: activeAlertId,
      predicate: (alert) => alert['acknowledged'] == true,
    );
    _expect(
      alert['acknowledged'] == true,
      'Expected alert to be acknowledged.',
    );
  });

  await _step(
    'Second caregiver acknowledgement state remains independent',
    () async {
      final alert = await _pollAlert(
        client: client,
        caregiverToken: secondCaregiverDevice.token,
        alertId: activeAlertId,
      );
      _expect(
        alert['acknowledged'] == false,
        'Expected first caregiver acknowledgement not to acknowledge the second caregiver view.',
      );
    },
  );

  late String cancelledAlertId;
  await _step('Assisted app records a cancelled fall alert', () async {
    final response = await client.post(
      '/api/v1/fall-alerts',
      token: protectedDevice.token,
      body: {
        'clientAlertId': 'e2e-cancelled-$runId',
        'fallTimestamp': DateTime.now().toUtc().toIso8601String(),
        'locale': 'fr_FR',
        'latitude': 43.6047,
        'longitude': 1.4442,
        'cancelled': true,
      },
    );
    _expectStatus(response, HttpStatus.created);
    cancelledAlertId = _stringField(response.json, 'id');
  });

  await _step(
    'Caregiver app history includes the assisted-cancelled alert',
    () async {
      final alert = await _pollAlert(
        client: client,
        caregiverToken: caregiverDevice.token,
        alertId: cancelledAlertId,
        predicate: (alert) => alert['status'] == 'cancelled',
      );
      _expect(
        alert['status'] == 'cancelled',
        'Expected cancelled alert status.',
      );
      _expect(
        alert['cancelledAt'] != null,
        'Expected cancelled alert timestamp.',
      );
      _expect(
        alert['acknowledged'] == false,
        'Expected cancelled alert to stay unacknowledged.',
      );
    },
  );

  await _step(
    'Second caregiver app history includes the assisted-cancelled alert',
    () async {
      final alert = await _pollAlert(
        client: client,
        caregiverToken: secondCaregiverDevice.token,
        alertId: cancelledAlertId,
        predicate: (alert) => alert['status'] == 'cancelled',
      );
      _expect(
        alert['status'] == 'cancelled',
        'Expected second caregiver cancelled alert status.',
      );
      _expect(
        alert['cancelledAt'] != null,
        'Expected second caregiver cancelled alert timestamp.',
      );
    },
  );

  stdout.writeln('');
  stdout.writeln('E2E workflow passed.');
}

Future<Map<String, dynamic>> _pollAlert({
  required _ApiClient client,
  required String caregiverToken,
  required String alertId,
  bool Function(Map<String, dynamic> alert)? predicate,
}) async {
  final accept = predicate ?? (_) => true;
  final deadline = DateTime.now().add(const Duration(seconds: 15));

  while (DateTime.now().isBefore(deadline)) {
    final response = await client.get(
      '/api/v1/caregiver/alerts',
      token: caregiverToken,
    );
    _expectStatus(response, HttpStatus.ok);

    for (final alert in _collection(response.json)) {
      if (alert['id'] == alertId && accept(alert)) {
        return alert;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  throw _E2eFailure('Timed out waiting for caregiver alert $alertId.');
}

Future<void> _step(String label, Future<void> Function() body) async {
  stdout.writeln('-> $label');
  await body();
  stdout.writeln('  ok');
}

String _randomRunId() {
  final random = Random.secure();
  final value = List.generate(
    8,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return '${DateTime.now().millisecondsSinceEpoch}-$value';
}

List<Map<String, dynamic>> _collection(Object? json) {
  final items = switch (json) {
    final List<dynamic> list => list,
    final Map<String, dynamic> map =>
      map['hydra:member'] as List<dynamic>? ??
          map['member'] as List<dynamic>? ??
          const <dynamic>[],
    _ => throw _E2eFailure('Expected a collection response, got $json.'),
  };

  return [
    for (final item in items)
      if (item is Map<String, dynamic>) item,
  ];
}

String _stringField(Object? json, String field) {
  if (json case final Map<String, dynamic> map) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }

  throw _E2eFailure('Expected non-empty string field "$field", got $json.');
}

void _expectStatus(_ApiResponse response, int expected) {
  _expect(
    response.statusCode == expected,
    'Expected HTTP $expected but got ${response.statusCode}. Body: ${response.body}',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw _E2eFailure(message);
  }
}

bool _isVisibleActiveStatus(Object? status) {
  return status == 'received' ||
      status == 'sent' ||
      status == 'partially_sent' ||
      status == 'failed';
}

final class _Config {
  const _Config({required this.baseUrl});

  factory _Config.fromArgs(List<String> args) {
    var baseUrl =
        Platform.environment['BACKEND_BASE_URL'] ?? 'http://127.0.0.1:8002';
    for (final arg in args) {
      if (arg.startsWith('--base-url=')) {
        baseUrl = arg.substring('--base-url='.length);
      }
    }

    return _Config(baseUrl: baseUrl.replaceFirst(RegExp(r'/$'), ''));
  }

  final String baseUrl;
}

final class _ApiClient {
  _ApiClient(this.baseUrl);

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Future<_Device> registerDevice({
    required String platform,
    required String deviceType,
    required String appVersion,
  }) async {
    final response = await post(
      '/api/v1/devices/register',
      body: {
        'platform': platform,
        'appVersion': appVersion,
        'deviceType': deviceType,
      },
    );
    _expectStatus(response, HttpStatus.created);

    return _Device(
      id: _stringField(response.json, 'deviceId'),
      token: _stringField(response.json, 'deviceToken'),
    );
  }

  Future<_ApiResponse> get(String path, {String? token}) {
    return _send(method: 'GET', path: path, token: token);
  }

  Future<_ApiResponse> post(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) {
    return _send(method: 'POST', path: path, token: token, body: body);
  }

  Future<_ApiResponse> _send({
    required String method,
    required String path,
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final responseBody = await response.transform(utf8.decoder).join();
    Object? decoded;
    if (responseBody.isNotEmpty) {
      decoded = jsonDecode(responseBody);
    }

    return _ApiResponse(
      statusCode: response.statusCode,
      body: responseBody,
      json: decoded,
    );
  }
}

final class _ApiResponse {
  const _ApiResponse({
    required this.statusCode,
    required this.body,
    required this.json,
  });

  final int statusCode;
  final String body;
  final Object? json;
}

final class _Device {
  const _Device({required this.id, required this.token});

  final String id;
  final String token;
}

final class _E2eFailure implements Exception {
  const _E2eFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
