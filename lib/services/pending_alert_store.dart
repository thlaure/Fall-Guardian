import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingAlertStore {
  static const _key = 'pending_fall_alert';

  Future<void> save(Map<String, dynamic> data) async {
    if (!_looksLikeFallAlert(data)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> take() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return null;
    }

    await prefs.remove(_key);

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
