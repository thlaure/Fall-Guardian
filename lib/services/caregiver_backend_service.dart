import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CaregiverBackendService {
  CaregiverBackendService({
    FlutterSecureStorage? storage,
    http.Client? client,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  static const _deviceIdKey = 'caregiver_device_id';
  static const _deviceTokenKey = 'caregiver_device_token';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  String get _baseUrl {
    const defined = String.fromEnvironment('BACKEND_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8002';
    }

    return 'http://127.0.0.1:8002';
  }

  Future<void> ensureRegistered() async {
    await _credentials();
  }

  Future<void> acceptInvite(String code) async {
    final credentials = await _credentials();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/invites/$code/accept'),
      headers: _jsonHeaders(token: credentials.deviceToken),
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to accept invite',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<void> acknowledgeFallAlert(String alertId) async {
    final credentials = await _credentials();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/fall-alerts/$alertId/acknowledge'),
      headers: _jsonHeaders(token: credentials.deviceToken),
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
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/v1/caregiver/alerts'),
      headers: _jsonHeaders(token: credentials.deviceToken),
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to fetch caregiver alerts',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    // API Platform wraps collections in hydra:member
    final wrapped = decoded as Map<String, dynamic>;
    final members = wrapped['hydra:member'] as List<dynamic>? ?? [];
    return members.cast<Map<String, dynamic>>();
  }

  Future<void> registerPushToken(String fcmToken) async {
    final credentials = await _credentials();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/caregiver/push-token'),
      headers: _jsonHeaders(token: credentials.deviceToken),
      body: jsonEncode({'fcmToken': fcmToken}),
    );

    if (!_isSuccess(response.statusCode)) {
      throw CaregiverApiException(
        'Failed to register push token',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<_CaregiverCredentials> _credentials() async {
    final deviceId = await _storage.read(key: _deviceIdKey);
    final deviceToken = await _storage.read(key: _deviceTokenKey);

    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceToken != null &&
        deviceToken.isNotEmpty) {
      return _CaregiverCredentials(deviceId: deviceId, deviceToken: deviceToken);
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/api/v1/devices/register'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'appVersion': '1.0.0',
        'deviceType': 'caregiver',
      }),
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

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;
}

class CaregiverApiException implements Exception {
  CaregiverApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'CaregiverApiException($message, $statusCode, $body)';
}

class _CaregiverCredentials {
  const _CaregiverCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
