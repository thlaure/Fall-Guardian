import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/api_date_time.dart';

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

    if (Platform.isIOS) {
      throw StateError(
        'BACKEND_BASE_URL must be set for iOS physical development builds.',
      );
    }

    return 'http://127.0.0.1:8002';
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
    var credentials = await _credentials();
    var response = await _getLinkedProtectedPersons(credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _getLinkedProtectedPersons(credentials);
    }

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to fetch linked protected persons',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final protectedPersons = _decodeCollection(
      jsonDecode(response.body),
    ).map(LinkedProtectedPerson.fromJson).toList();

    protectedPersons.sort(_namedProtectedPersonsFirst);

    return protectedPersons;
  }

  Future<http.Response> _getLinkedProtectedPersons(
    _CaregiverCredentials credentials,
  ) {
    return _send(
      _client.get(
        Uri.parse('$_baseUrl/api/v1/caregiver/protected-persons'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Linked protected persons fetch timed out',
    );
  }

  Future<void> acceptInvite(
    String code, {
    required String protectedPersonName,
    required String caregiverName,
  }) async {
    var credentials = await _credentials();
    var response = await _acceptInvite(
      code,
      credentials,
      protectedPersonName: protectedPersonName,
      caregiverName: caregiverName,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _acceptInvite(
        code,
        credentials,
        protectedPersonName: protectedPersonName,
        caregiverName: caregiverName,
      );
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
    _CaregiverCredentials credentials, {
    required String protectedPersonName,
    required String caregiverName,
  }) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/invites/$code/accept'),
        headers: _jsonHeaders(token: credentials.deviceToken),
        body: jsonEncode({
          'protectedPersonName': protectedPersonName.trim(),
          'caregiverName': caregiverName.trim(),
        }),
      ),
      'Invite acceptance timed out',
    );
  }

  Future<void> acknowledgeFallAlert(String alertId) async {
    var credentials = await _credentials();
    var response = await _acknowledgeFallAlert(alertId, credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _acknowledgeFallAlert(alertId, credentials);
    }

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to acknowledge alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<http.Response> _acknowledgeFallAlert(
    String alertId,
    _CaregiverCredentials credentials,
  ) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts/$alertId/acknowledge'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Fall alert acknowledgement timed out',
    );
  }

  Future<List<Map<String, dynamic>>> getCaregiverAlerts() async {
    var credentials = await _credentials();
    var response = await _getCaregiverAlerts(credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _getCaregiverAlerts(credentials);
    }

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

  Future<http.Response> _getCaregiverAlerts(_CaregiverCredentials credentials) {
    return _send(
      _client.get(
        Uri.parse('$_baseUrl/api/v1/caregiver/alerts'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Caregiver alerts fetch timed out',
    );
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
    var credentials = await _credentials();
    var response = await _registerPushToken(fcmToken, credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _registerPushToken(fcmToken, credentials);
    }

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to register push token',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<http.Response> _registerPushToken(
    String fcmToken,
    _CaregiverCredentials credentials,
  ) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/caregiver/push-token'),
        headers: _jsonHeaders(token: credentials.deviceToken),
        body: jsonEncode({'fcmToken': fcmToken}),
      ),
      'Push token registration timed out',
    );
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
    final leftDate = parseApiDateTime('${left['fallDetectedAt']}');
    final rightDate = parseApiDateTime('${right['fallDetectedAt']}');
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

  int _namedProtectedPersonsFirst(
    LinkedProtectedPerson left,
    LinkedProtectedPerson right,
  ) {
    final leftHasName = left.hasProtectedPersonName;
    final rightHasName = right.hasProtectedPersonName;
    if (leftHasName != rightHasName) {
      return leftHasName ? -1 : 1;
    }

    return left.protectedDeviceId.compareTo(right.protectedDeviceId);
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
    required this.protectedPersonName,
  });

  factory LinkedProtectedPerson.fromJson(Map<String, dynamic> json) {
    return LinkedProtectedPerson(
      protectedDeviceId: '${json['protectedDeviceId'] ?? 'unknown'}',
      protectedDevicePlatform:
          '${json['protectedDevicePlatform'] ?? 'unknown'}',
      protectedPersonName: (json['protectedPersonName'] as String?)?.trim(),
    );
  }

  final String protectedDeviceId;
  final String protectedDevicePlatform;
  final String? protectedPersonName;

  bool get hasProtectedPersonName =>
      protectedPersonName != null && protectedPersonName!.isNotEmpty;
}

class _CaregiverCredentials {
  const _CaregiverCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
