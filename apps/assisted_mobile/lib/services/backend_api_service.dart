import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/contact.dart';
import 'alert_ports.dart';
import 'secure_store.dart';

class BackendApiService implements AlertBackendGateway {
  BackendApiService({
    KeyValueStore? store,
    http.Client? client,
    String? baseUrl,
    bool? releaseMode,
    Duration? requestTimeout,
  })  : _store = store ?? SecureKeyValueStore(),
        _client = client ?? http.Client(),
        _baseUrlOverride = baseUrl,
        _releaseMode = releaseMode ?? kReleaseMode,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 10);

  static const _deviceIdKey = 'backend_device_id';
  static const _deviceTokenKey = 'backend_device_token';

  final KeyValueStore _store;
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

  @override
  Future<void> ensureReady() async {
    var credentials = await _credentials();
    final response = await _getLinkedCaregivers(credentials);
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      credentials = await _credentials(forceRefresh: true);
      final refreshedResponse = await _getLinkedCaregivers(credentials);
      if (!_isSuccess(refreshedResponse.statusCode)) {
        throw BackendApiException(
          'Failed to validate refreshed device credentials',
          statusCode: refreshedResponse.statusCode,
          body: refreshedResponse.body,
        );
      }
      return;
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to validate device credentials',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  @override
  Future<void> syncContacts(List<Contact> contacts) async {
    await _credentials();
  }

  @override
  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    required List<Contact> contacts,
  }) async {
    var credentials = await _credentials();
    var response = await _submitFallAlert(
      credentials: credentials,
      clientAlertId: clientAlertId,
      fallTimestamp: fallTimestamp,
      locale: locale,
      latitude: latitude,
      longitude: longitude,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _submitFallAlert(
        credentials: credentials,
        clientAlertId: clientAlertId,
        fallTimestamp: fallTimestamp,
        locale: locale,
        latitude: latitude,
        longitude: longitude,
      );
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to submit fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    // The API acknowledges that the alert was accepted for dispatch. Actual
    // caregiver push delivery happens asynchronously on the backend worker.
  }

  Future<http.Response> _submitFallAlert({
    required _BackendCredentials credentials,
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts'),
        headers: _jsonHeaders(token: credentials.deviceToken),
        body: jsonEncode(_fallAlertPayload(
          clientAlertId: clientAlertId,
          fallTimestamp: fallTimestamp,
          locale: locale,
          latitude: latitude,
          longitude: longitude,
        )),
      ),
      'Fall alert submission timed out',
    );
  }

  @override
  Future<void> recordCancelledFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    var credentials = await _credentials();
    var response = await _recordCancelledFallAlert(
      credentials: credentials,
      clientAlertId: clientAlertId,
      fallTimestamp: fallTimestamp,
      locale: locale,
      latitude: latitude,
      longitude: longitude,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _recordCancelledFallAlert(
        credentials: credentials,
        clientAlertId: clientAlertId,
        fallTimestamp: fallTimestamp,
        locale: locale,
        latitude: latitude,
        longitude: longitude,
      );
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to record cancelled fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<http.Response> _recordCancelledFallAlert({
    required _BackendCredentials credentials,
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts'),
        headers: _jsonHeaders(token: credentials.deviceToken),
        body: jsonEncode(_fallAlertPayload(
          clientAlertId: clientAlertId,
          fallTimestamp: fallTimestamp,
          locale: locale,
          latitude: latitude,
          longitude: longitude,
          cancelled: true,
        )),
      ),
      'Cancelled fall alert recording timed out',
    );
  }

  Future<Map<String, dynamic>> createInvite() async {
    var credentials = await _credentials();
    var response = await _createInvite(credentials);
    if (response.statusCode == HttpStatus.unauthorized) {
      credentials = await _credentials(forceRefresh: true);
      response = await _createInvite(credentials);
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to create caregiver invite',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _createInvite(_BackendCredentials credentials) {
    return _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/invites'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Invite creation timed out',
    );
  }

  @override
  Future<void> cancelFallAlert({required String clientAlertId}) async {
    final token = await _store.read(_deviceTokenKey);
    if (token == null || token.isEmpty) {
      return;
    }

    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts/$clientAlertId/cancel'),
        headers: _jsonHeaders(token: token),
      ),
      'Fall alert cancellation timed out',
    );

    if (response.statusCode == 404) {
      return;
    }

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to cancel fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getLinkedCaregivers() async {
    final credentials = await _credentials();
    final response = await _getLinkedCaregivers(credentials);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to fetch linked caregivers',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<http.Response> _getLinkedCaregivers(
    _BackendCredentials credentials,
  ) {
    return _send(
      _client.get(
        Uri.parse('$_baseUrl/api/v1/protected/linked-caregivers'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Linked caregivers request timed out',
    );
  }

  Future<void> deleteLinkedCaregiver(String linkId) async {
    final credentials = await _credentials();
    final response = await _send(
      _client.delete(
        Uri.parse('$_baseUrl/api/v1/protected/linked-caregivers/$linkId'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Remove caregiver request timed out',
    );

    if (response.statusCode != 204) {
      throw BackendApiException(
        'Failed to remove caregiver link',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<_BackendCredentials> _credentials({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final deviceId = await _store.read(_deviceIdKey);
      final deviceToken = await _store.read(_deviceTokenKey);
      if (deviceId != null &&
          deviceId.isNotEmpty &&
          deviceToken != null &&
          deviceToken.isNotEmpty) {
        return _BackendCredentials(
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
          'deviceType': 'protected_person',
        }),
      ),
      'Device registration timed out',
    );

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to register device',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final credentials = _BackendCredentials(
      deviceId: payload['deviceId'] as String,
      deviceToken: payload['deviceToken'] as String,
    );

    await _store.write(_deviceIdKey, credentials.deviceId);
    await _store.write(_deviceTokenKey, credentials.deviceToken);
    developer.log(
      'Registered device with backend ${credentials.deviceId}',
      name: 'BackendApiService',
    );
    return credentials;
  }

  Map<String, dynamic> _fallAlertPayload({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
    bool cancelled = false,
  }) {
    return {
      'clientAlertId': clientAlertId,
      'fallTimestamp':
          DateTime.fromMillisecondsSinceEpoch(fallTimestamp, isUtc: true)
              .toIso8601String(),
      'locale': locale,
      'latitude': latitude,
      'longitude': longitude,
      if (cancelled) 'cancelled': true,
    };
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
      throw BackendApiException(timeoutMessage);
    }
  }
}

class BackendApiException implements Exception {
  BackendApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'BackendApiException($message, $statusCode, $body)';
}

class _BackendCredentials {
  const _BackendCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
