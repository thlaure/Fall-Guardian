import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CaregiverBackendService {
  CaregiverBackendService({
    FlutterSecureStorage? storage,
    http.Client? client,
    String? baseUrl,
    bool? releaseMode,
    Duration? requestTimeout,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       _baseUrlOverride = baseUrl,
       _releaseMode = releaseMode ?? kReleaseMode,
       _requestTimeout = requestTimeout ?? const Duration(seconds: 10);

  static const _deviceIdKey = 'caregiver_device_id';
  static const _deviceTokenKey = 'caregiver_device_token';
  static const _linkedKey = 'caregiver_linked';

  final FlutterSecureStorage _storage;
  final http.Client _client;
  final String? _baseUrlOverride;
  final bool _releaseMode;
  final Duration _requestTimeout;

  // On a physical iOS device 127.0.0.1 resolves to the phone, not the Mac.
  // Update this to your dev machine's LAN IP when testing on a real device,
  // or pass --dart-define=BACKEND_BASE_URL=http://<lan-ip>:8002 at build time.
  static const _devMachineLanIp = '172.16.20.73';

  String get _baseUrl {
    if (_baseUrlOverride case final override? when override.isNotEmpty) {
      return _validateBaseUrl(override);
    }

    const defined = String.fromEnvironment('BACKEND_BASE_URL');
    if (defined.isNotEmpty) {
      return _validateBaseUrl(defined);
    }

    if (_releaseMode) {
      throw StateError('BACKEND_BASE_URL must be set for release builds.');
    }

    return 'http://$_devMachineLanIp:8002';
  }

  String _validateBaseUrl(String baseUrl) {
    if (_releaseMode && Uri.tryParse(baseUrl)?.scheme != 'https') {
      throw StateError('BACKEND_BASE_URL must use HTTPS for release builds.');
    }

    return baseUrl;
  }

  Future<void> ensureRegistered() async {
    await _credentials();
  }

  Future<bool> isLinked() async {
    return await _storage.read(key: _linkedKey) == 'true';
  }

  Future<void> markUnlinked() async {
    await _storage.write(key: _linkedKey, value: 'false');
  }

  Future<bool> refreshLinkedProtectedPersons() async {
    final protectedPersons = await getLinkedProtectedPersons();
    final linked = protectedPersons.isNotEmpty;
    await _storage.write(key: _linkedKey, value: linked ? 'true' : 'false');

    return linked;
  }

  Future<List<LinkedProtectedPerson>> getLinkedProtectedPersons() async {
    final credentials = await _credentials();
    final response = await _send(
      _client.get(
        Uri.parse('$_baseUrl/api/v1/caregiver/protected-persons'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Linked protected persons fetch timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to fetch linked protected persons',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return _decodeCollection(
      jsonDecode(response.body),
    ).map(LinkedProtectedPerson.fromJson).toList();
  }

  Future<void> acceptInvite(String code) async {
    var credentials = await _credentials();
    var response = await _acceptInvite(code, credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _acceptInvite(code, credentials);
    }

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to accept invite',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    await _storage.write(key: _linkedKey, value: 'true');
  }

  Future<http.Response> _acceptInvite(
    String code,
    _CaregiverCredentials credentials,
  ) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/invites/$code/accept'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Invite acceptance timed out',
    );
  }

  Future<void> acknowledgeFallAlert(String alertId) async {
    final credentials = await _credentials();
    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts/$alertId/acknowledge'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Fall alert acknowledgement timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to acknowledge alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getCaregiverAlerts() async {
    final credentials = await _credentials();
    final response = await _send(
      _client.get(
        Uri.parse('$_baseUrl/api/v1/caregiver/alerts'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Caregiver alerts fetch timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to fetch caregiver alerts',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    return _decodeAlertCollection(decoded);
  }

  Future<Map<String, dynamic>?> getLatestActiveAlertData() async {
    final activeAlerts =
        (await getCaregiverAlerts())
            .where(_isActiveUnacknowledgedAlert)
            .toList()
          ..sort(_newestAlertFirst);

    if (activeAlerts.isEmpty) {
      return null;
    }

    return _toPushAlertData(activeAlerts.first);
  }

  Future<void> registerPushToken(String fcmToken) async {
    final credentials = await _credentials();
    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/caregiver/push-token'),
        headers: _jsonHeaders(token: credentials.deviceToken),
        body: jsonEncode({'fcmToken': fcmToken}),
      ),
      'Push token registration timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to register push token',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<_CaregiverCredentials> _credentials({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final deviceId = await _storage.read(key: _deviceIdKey);
      final deviceToken = await _storage.read(key: _deviceTokenKey);

      if (deviceId != null &&
          deviceId.isNotEmpty &&
          deviceToken != null &&
          deviceToken.isNotEmpty) {
        return _CaregiverCredentials(
          deviceId: deviceId,
          deviceToken: deviceToken,
        );
      }
    }

    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/devices/register'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'appVersion': '1.0.0',
          'deviceType': 'caregiver',
        }),
      ),
      'Caregiver device registration timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to register caregiver device',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final credentials = _CaregiverCredentials(
      deviceId: payload['deviceId'] as String,
      deviceToken: payload['deviceToken'] as String,
    );

    await _storage.write(key: _deviceIdKey, value: credentials.deviceId);
    await _storage.write(key: _deviceTokenKey, value: credentials.deviceToken);
    developer.log(
      'Registered caregiver device ${credentials.deviceId}',
      name: 'CaregiverBackendService',
    );

    return credentials;
  }

  /// Normalizes the two collection shapes the API can return.
  ///
  /// Some test/dev endpoints return a plain JSON array. API Platform collection
  /// endpoints usually wrap items in a `hydra:member` field. The UI should not
  /// need to know which wire shape was used, so this service converts both into
  /// a single `List<Map<String, dynamic>>`.
  List<Map<String, dynamic>> _decodeAlertCollection(Object? decoded) {
    return _decodeCollection(decoded);
  }

  List<Map<String, dynamic>> _decodeCollection(Object? decoded) {
    final items = switch (decoded) {
      final List<dynamic> list => list,
      final Map<String, dynamic> wrapper =>
        wrapper['hydra:member'] as List<dynamic>? ?? const <dynamic>[],
      _ => throw const FormatException('Unexpected caregiver alerts response'),
    };

    return [
      for (final item in items)
        if (item is Map<String, dynamic>) item,
    ];
  }

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

  Future<http.Response> _send(
    Future<http.Response> request,
    String timeoutMessage,
  ) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw CaregiverApiException(timeoutMessage);
    }
  }

  bool _isActiveUnacknowledgedAlert(Map<String, dynamic> alert) {
    return alert['acknowledged'] != true && alert['status'] != 'cancelled';
  }

  int _newestAlertFirst(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftDate = DateTime.tryParse('${left['fallDetectedAt']}');
    final rightDate = DateTime.tryParse('${right['fallDetectedAt']}');
    if (leftDate == null && rightDate == null) return 0;
    if (leftDate == null) return 1;
    if (rightDate == null) return -1;
    return rightDate.compareTo(leftDate);
  }

  Map<String, dynamic> _toPushAlertData(Map<String, dynamic> alert) {
    return {
      'alertId': '${alert['id']}',
      'fallTimestamp': '${alert['fallDetectedAt']}',
      if (alert['latitude'] != null) 'latitude': '${alert['latitude']}',
      if (alert['longitude'] != null) 'longitude': '${alert['longitude']}',
    };
  }
}

class CaregiverApiException implements Exception {
  CaregiverApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'CaregiverApiException($message, $statusCode, $body)';
}

class LinkedProtectedPerson {
  const LinkedProtectedPerson({
    required this.protectedDeviceId,
    required this.protectedDevicePlatform,
  });

  factory LinkedProtectedPerson.fromJson(Map<String, dynamic> json) {
    return LinkedProtectedPerson(
      protectedDeviceId: '${json['protectedDeviceId'] ?? 'unknown'}',
      protectedDevicePlatform:
          '${json['protectedDevicePlatform'] ?? 'unknown'}',
    );
  }

  final String protectedDeviceId;
  final String protectedDevicePlatform;
}

class _CaregiverCredentials {
  const _CaregiverCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
