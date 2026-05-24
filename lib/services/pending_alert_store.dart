import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingAlertStore {
  PendingAlertStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(iOptions: _iosOptions);

  static const _key = 'pending_fall_alert';
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage;

  Future<void> save(Map<String, dynamic> data) async {
    if (!_looksLikeFallAlert(data)) {
      return;
    }

    // Alerts may contain location and arrive while the phone is locked. On
    // iOS the selected keychain class permits background access after the
    // device has been unlocked once, without allowing migration to a new device.
    await _storage.write(key: _key, value: jsonEncode(data));
    final legacyPrefs = await SharedPreferences.getInstance();
    await legacyPrefs.remove(_key);
  }

  Future<Map<String, dynamic>?> take() async {
    var raw = await _storage.read(key: _key);
    await _storage.delete(key: _key);

    // Read and remove old plaintext state once so an update does not discard an
    // alert received before encrypted persistence was introduced.
    final legacyPrefs = await SharedPreferences.getInstance();
    raw ??= legacyPrefs.getString(_key);
    await legacyPrefs.remove(_key);

    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || !_looksLikeFallAlert(decoded)) {
      return null;
    }

    return decoded;
  }

  bool _looksLikeFallAlert(Map<String, dynamic> data) {
    final alertId = data['alertId'];
    final fallTimestamp = data['fallTimestamp'];
    return alertId is String &&
        alertId.isNotEmpty &&
        fallTimestamp is String &&
        fallTimestamp.isNotEmpty;
  }
}
