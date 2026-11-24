import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/contact.dart';
import 'alert_ports.dart';
import 'device_pairing_state.dart';
import 'device_registration_marker.dart';
import 'secure_store.dart';

class BackendApiService implements AlertBackendGateway {
  BackendApiService({
    KeyValueStore? store,
    http.Client? client,
    String? baseUrl,
    bool? releaseMode,
    Duration? requestTimeout,
    bool? isIOSPlatform,
    List<Duration>? submitRetryDelays,
    List<Duration>? cancellationRetryDelays,
    DevicePairingState? pairingState,
    DeviceRegistrationMarker? registrationMarker,
  })  : _store = store ?? SecureKeyValueStore(),
        _registrationMarker =
            registrationMarker ?? const SharedPreferencesRegistrationMarker(),
        _pairingState = pairingState ?? DevicePairingState.shared,
        _client = client ?? http.Client(),
        _baseUrlOverride = baseUrl,
        _releaseMode = releaseMode ?? kReleaseMode,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 10),
        _isIOSPlatform = isIOSPlatform ?? Platform.isIOS,
        _submitRetryDelays = submitRetryDelays ??
            const [Duration(milliseconds: 500), Duration(seconds: 2)],
        _cancellationRetryDelays = cancellationRetryDelays ??
            const [Duration(milliseconds: 200), Duration(milliseconds: 500)];

  static const _deviceIdKey = 'backend_device_id';
  static const _deviceTokenKey = 'backend_device_token';

  /// Set (by Dart or the native relays) when the API rejected this phone's
  /// credentials. Shared secure-store key — must match NativeAlertRelay.kt
  /// and NativeAppleWatchAlertRelay.swift.
  static const reauthRequiredKey = 'backend_reauth_required';

  final KeyValueStore _store;
  final DevicePairingState _pairingState;
  final DeviceRegistrationMarker _registrationMarker;
  final http.Client _client;
  final String? _baseUrlOverride;
  final bool _releaseMode;
  final Duration _requestTimeout;
  final bool _isIOSPlatform;

  // The initial fall-alert submission is now the single safety-critical
  // call (the backend owns the cancel/grace timer once it lands) — retry a
  // couple of times on transient failure instead of giving up on the first
  // blip.
  final List<Duration> _submitRetryDelays;
  final List<Duration> _cancellationRetryDelays;

  String get debugBaseUrl => _baseUrl;

  String get _baseUrl {
    if (_baseUrlOverride case final override? when override.isNotEmpty) {
      return _validateBaseUrl(override);
    }

    // Compile-time constant: only ever non-empty when the binary is built
    // with --dart-define=BACKEND_BASE_URL=..., which unit tests don't do.
    // coverage:ignore-start
    const defined = String.fromEnvironment('BACKEND_BASE_URL');
    if (defined.isNotEmpty) {
      return _validateBaseUrl(defined);
    }
    // coverage:ignore-end

    if (_releaseMode) {
      throw StateError('BACKEND_BASE_URL must be set for release builds.');
    }

    if (_isIOSPlatform) {
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

  /// Validates the stored credentials against the API.
  ///
  /// A 401/403 means the backend no longer knows this phone. Registering a
  /// fresh device silently would create an orphan with no caregiver links —
  /// alerts would then reach nobody while the UI claimed success — so this
  /// instead enters the explicit re-pairing state ([repairDevice]).
  @override
  Future<void> ensureReady() async {
    final credentials = await _credentials();
    final response = await _getLinkedCaregivers(credentials);
    await _throwIfCredentialsRejected(response);

    if (_isSuccess(response.statusCode)) {
      // The server accepts the stored token again: clear any stale flag.
      await _clearRepairRequired();
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
  Future<FallAlertReceipt?> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _submitFallAlertOnce(
          clientAlertId: clientAlertId,
          fallTimestamp: fallTimestamp,
          locale: locale,
          latitude: latitude,
          longitude: longitude,
        );
        // The API acknowledges the alert was accepted; the backend now owns
        // the grace/cancel window and dispatches the caregiver push itself.
      } catch (error) {
        final canRetry =
            attempt < _submitRetryDelays.length && _isRetryableFailure(error);
        if (!canRetry) rethrow;
        await Future<void>.delayed(_submitRetryDelays[attempt]);
      }
    }
  }

  // A 4xx is a permanent client error that retrying will never fix (401/403
  // surface as [DeviceRepairRequiredException]). Timeouts (no status code),
  // 408, 429 and 5xx server errors are worth retrying.
  bool _isRetryableFailure(Object error) {
    if (error is DeviceRepairRequiredException) return false;
    if (error is! BackendApiException) return true;
    final statusCode = error.statusCode;
    return statusCode == null ||
        statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests ||
        statusCode >= 500;
  }

  Future<FallAlertReceipt?> _submitFallAlertOnce({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    final credentials = await _credentials();
    final roundTrip = Stopwatch()..start();
    final response = await _submitFallAlert(
      credentials: credentials,
      clientAlertId: clientAlertId,
      fallTimestamp: fallTimestamp,
      locale: locale,
      latitude: latitude,
      longitude: longitude,
    );
    roundTrip.stop();
    await _throwIfCredentialsRejected(response);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to submit fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return fallAlertReceiptFrom(response, roundTrip: roundTrip.elapsed);
  }

  /// Derives the remaining server-owned grace period from a create response.
  ///
  /// remaining = cancelDeadlineAt − serverNow − roundTrip, all from server
  /// timestamps, so the phone's wall clock (which may be skewed) is never
  /// compared with server time. serverNow is the later of `receivedAt` and
  /// the HTTP `Date` header: for an idempotent replay of an older alert
  /// `receivedAt` is in the past and `Date` is the better "now". Subtracting
  /// the full round trip errs on the side of showing less time, never more.
  @visibleForTesting
  static FallAlertReceipt? fallAlertReceiptFrom(
    http.Response response, {
    required Duration roundTrip,
  }) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      final deadline = DateTime.tryParse('${payload['cancelDeadlineAt']}');
      final receivedAt = DateTime.tryParse('${payload['receivedAt']}');
      if (deadline == null || receivedAt == null) return null;

      var serverNow = receivedAt;
      final dateHeader = response.headers['date'];
      if (dateHeader != null) {
        try {
          final headerNow = HttpDate.parse(dateHeader);
          if (headerNow.isAfter(serverNow)) serverNow = headerNow;
        } on FormatException {
          // Keep receivedAt.
        } on HttpException {
          // Keep receivedAt.
        }
      }

      final remaining = deadline.difference(serverNow) - roundTrip;
      return FallAlertReceipt(
        remainingGrace: remaining.isNegative ? Duration.zero : remaining,
      );
    } on FormatException {
      return null;
    }
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
    for (var attempt = 0;; attempt++) {
      try {
        await _recordCancelledFallAlertOnce(
          clientAlertId: clientAlertId,
          fallTimestamp: fallTimestamp,
          locale: locale,
          latitude: latitude,
          longitude: longitude,
        );
        return;
      } catch (error) {
        final canRetry = attempt < _cancellationRetryDelays.length &&
            _isRetryableFailure(error);
        if (!canRetry) rethrow;
        await Future<void>.delayed(_cancellationRetryDelays[attempt]);
      }
    }
  }

  Future<void> _recordCancelledFallAlertOnce({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  }) async {
    final credentials = await _credentials();
    final response = await _recordCancelledFallAlert(
      credentials: credentials,
      clientAlertId: clientAlertId,
      fallTimestamp: fallTimestamp,
      locale: locale,
      latitude: latitude,
      longitude: longitude,
    );
    await _throwIfCredentialsRejected(response);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to record cancelled fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    _requireCancelledResponse(
      response,
      'Backend did not confirm the cancelled fall alert',
    );
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
    final credentials = await _credentials();
    final response = await _createInvite(credentials);
    await _throwIfCredentialsRejected(response);

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
    for (var attempt = 0;; attempt++) {
      try {
        await _cancelFallAlertOnce(clientAlertId);
        return;
      } catch (error) {
        final canRetry = attempt < _cancellationRetryDelays.length &&
            _isRetryableFailure(error);
        if (!canRetry) rethrow;
        await Future<void>.delayed(_cancellationRetryDelays[attempt]);
      }
    }
  }

  Future<void> _cancelFallAlertOnce(String clientAlertId) async {
    final credentials = await _credentials();
    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts/$clientAlertId/cancel'),
        headers: _jsonHeaders(token: credentials.deviceToken),
      ),
      'Fall alert cancellation timed out',
    );
    await _throwIfCredentialsRejected(response);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to cancel fall alert',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    _requireCancelledResponse(
      response,
      'Backend did not confirm fall alert cancellation',
    );
  }

  @override
  Future<void> attachLocation({
    required String clientAlertId,
    required double latitude,
    required double longitude,
  }) async {
    final token = await _store.read(_deviceTokenKey);
    if (token == null || token.isEmpty) {
      return;
    }

    final response = await _send(
      _client.post(
        Uri.parse('$_baseUrl/api/v1/fall-alerts/$clientAlertId/location'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      ),
      'Fall alert location attachment timed out',
    );

    if (response.statusCode == 404) {
      return;
    }
    await _throwIfCredentialsRejected(response);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to attach fall alert location',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getLinkedCaregivers() async {
    final credentials = await _credentials();
    final response = await _getLinkedCaregivers(credentials);
    await _throwIfCredentialsRejected(response);

    if (!_isSuccess(response.statusCode)) {
      throw BackendApiException(
        'Failed to fetch linked caregivers',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final caregivers =
        (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();

    caregivers.sort(_namedCaregiversFirst);

    return caregivers;
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

  /// Whether this phone must be re-paired (persisted flag). Also refreshes
  /// the shared UI notifier.
  Future<bool> isRepairRequired() async {
    final required = await _store.read(reauthRequiredKey) == 'true';
    _pairingState.repairRequired.value = required;
    return required;
  }

  /// Explicit, user-initiated re-pairing: drops the rejected credentials and
  /// registers this phone again. The new registration has no caregiver
  /// links yet, so the user must send new invitations afterwards (the UI
  /// says so). Never called automatically.
  Future<void> repairDevice() async {
    await _store.delete(_deviceIdKey);
    await _store.delete(_deviceTokenKey);
    await _register();
    await _clearRepairRequired();
  }

  Future<void> _throwIfCredentialsRejected(http.Response response) async {
    if (response.statusCode != HttpStatus.unauthorized &&
        response.statusCode != HttpStatus.forbidden) {
      return;
    }
    await _store.write(reauthRequiredKey, 'true');
    _pairingState.repairRequired.value = true;
    throw DeviceRepairRequiredException(statusCode: response.statusCode);
  }

  Future<void> _clearRepairRequired() async {
    if (await _store.read(reauthRequiredKey) != null) {
      await _store.delete(reauthRequiredKey);
    }
    _pairingState.repairRequired.value = false;
  }

  Future<_BackendCredentials> _credentials() async {
    final deviceId = await _store.read(_deviceIdKey);
    final deviceToken = await _store.read(_deviceTokenKey);
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceToken != null &&
        deviceToken.isNotEmpty) {
      // Migration: installs registered before the marker existed (or iOS
      // reinstalls, where the Keychain outlives UserDefaults) get it now.
      if (!await _registrationMarker.isSet()) {
        await _registrationMarker.set();
      }
      return _BackendCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
      );
    }

    // Only a true first launch registers automatically. After a rejection,
    // or when credentials vanished from secure storage on a phone that had
    // registered (marker present), registering would create an orphan device
    // that no caregiver is linked to; re-pairing must be explicit.
    if (await _store.read(reauthRequiredKey) == 'true' ||
        await _registrationMarker.isSet()) {
      await _store.write(reauthRequiredKey, 'true');
      _pairingState.repairRequired.value = true;
      throw DeviceRepairRequiredException();
    }
    return _register();
  }

  Future<_BackendCredentials> _register() async {
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
    await _registrationMarker.set();
    // Never log the device id or token.
    developer.log('Registered device with backend', name: 'BackendApiService');
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

  void _requireCancelledResponse(http.Response response, String message) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] == 'cancelled') return;
    } catch (_) {
      // Converted below into a typed safety-critical confirmation failure.
    }

    throw BackendApiException(
      message,
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  int _namedCaregiversFirst(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftHasName = '${left['caregiverName'] ?? ''}'.trim().isNotEmpty;
    final rightHasName = '${right['caregiverName'] ?? ''}'.trim().isNotEmpty;
    if (leftHasName != rightHasName) {
      return leftHasName ? -1 : 1;
    }

    return '${right['linkedAt'] ?? ''}'.compareTo('${left['linkedAt'] ?? ''}');
  }

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

/// The API rejected this phone's credentials (401/403). Caregivers cannot be
/// notified until the user explicitly re-pairs the phone.
class DeviceRepairRequiredException extends BackendApiException {
  DeviceRepairRequiredException({int? statusCode})
      : super('Device re-pairing required', statusCode: statusCode);
}

class _BackendCredentials {
  const _BackendCredentials({
    required this.deviceId,
    required this.deviceToken,
  });

  final String deviceId;
  final String deviceToken;
}
