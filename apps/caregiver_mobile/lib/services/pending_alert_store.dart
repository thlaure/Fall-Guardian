import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'caregiver_secure_storage.dart';

/// Durable handoff for fall alerts received while the Flutter UI is not alive.
///
/// A caregiver can protect several people, so several alerts may arrive
/// before the app is opened. Alerts are kept as a bounded list keyed by
/// `alertId` (a repeated push for the same alert, e.g. a reminder, replaces
/// the earlier entry instead of duplicating it).
class PendingAlertStore {
  PendingAlertStore({FlutterSecureStorage? storage, this.maxAlerts = 10})
    : _storage = storage ?? caregiverSecureStorage;

  static const listKey = 'pending_fall_alerts';

  /// Single-alert key used by previous app versions (secure storage, and
  /// before that plaintext SharedPreferences). Migrated into [listKey].
  static const legacyKey = 'pending_fall_alert';

  final FlutterSecureStorage _storage;
  final int maxAlerts;

  /// Serialises read-modify-write cycles so two pushes arriving together do
  /// not overwrite each other. Shared by every store instance in this
  /// isolate. (The FCM background handler may run in another isolate; the
  /// window there is one push at a time per isolate.)
  static Future<void> _lock = Future<void>.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> save(Map<String, dynamic> data) async {
    if (!looksLikeFallAlert(data)) {
      return;
    }
    await _synchronized(() => _save(data));
  }

  Future<void> _save(Map<String, dynamic> data) async {
    // Alerts may contain location and arrive while the phone is locked. On
    // iOS the selected keychain class permits background access after the
    // device has been unlocked once, without allowing migration to a new device.
    final alerts = await _readAll();
    alerts.removeWhere((alert) => alert['alertId'] == data['alertId']);
    alerts.add(Map<String, dynamic>.of(data));
    while (alerts.length > maxAlerts) {
      alerts.removeAt(0);
    }
    await _writeAll(alerts);
    await _deleteLegacy();
  }

  /// Returns every pending alert, oldest first, and clears the store.
  Future<List<Map<String, dynamic>>> takeAll() => _synchronized(_takeAll);

  Future<List<Map<String, dynamic>>> _takeAll() async {
    final alerts = await _readAll();
    await _storage.delete(key: listKey);
    await _deleteLegacy();
    return alerts;
  }

  /// Removes one alert, e.g. because the user opened its notification and
  /// the alert is being presented from the notification payload.
  Future<void> remove(String alertId) => _synchronized(() => _remove(alertId));

  Future<void> _remove(String alertId) async {
    final alerts = await _readAll();
    final before = alerts.length;
    alerts.removeWhere((alert) => alert['alertId'] == alertId);
    if (alerts.length != before) {
      await _writeAll(alerts);
    }
  }

  /// Reads the list plus any legacy single entry. Legacy data is only deleted
  /// by callers after the merged list was written successfully.
  Future<List<Map<String, dynamic>>> _readAll() async {
    final alerts = _decodeList(await _storage.read(key: listKey));

    final legacyRaws = <String?>[
      await _storage.read(key: legacyKey),
      (await SharedPreferences.getInstance()).getString(legacyKey),
    ];
    for (final raw in legacyRaws) {
      final legacy = _decodeAlert(raw);
      if (legacy != null &&
          !alerts.any((alert) => alert['alertId'] == legacy['alertId'])) {
        alerts.insert(0, legacy);
      }
    }

    return alerts;
  }

  Future<void> _writeAll(List<Map<String, dynamic>> alerts) async {
    if (alerts.isEmpty) {
      await _storage.delete(key: listKey);
      return;
    }
    await _storage.write(key: listKey, value: jsonEncode(alerts));
  }

  Future<void> _deleteLegacy() async {
    await _storage.delete(key: legacyKey);
    final legacyPrefs = await SharedPreferences.getInstance();
    await legacyPrefs.remove(legacyKey);
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> && looksLikeFallAlert(item)) item,
      ];
    } on FormatException catch (error) {
      developer.log(
        'Discarding unreadable pending alerts: $error',
        name: 'PendingAlertStore',
      );
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic>? _decodeAlert(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && looksLikeFallAlert(decoded)
          ? decoded
          : null;
    } on FormatException {
      return null;
    }
  }

  static bool looksLikeFallAlert(Map<String, dynamic> data) {
    final alertId = data['alertId'];
    final fallTimestamp = data['fallTimestamp'];
    return alertId is String &&
        alertId.isNotEmpty &&
        fallTimestamp is String &&
        fallTimestamp.isNotEmpty;
  }
}
