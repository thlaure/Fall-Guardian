import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_sms/flutter_sms.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';

class SmsService {
  static DateTime? _lastSentAt;
  static const _kLastSentAtMs = 'sms_last_sent_at_ms';

  /// Resets the in-memory rate-limiting state. Only for use in tests.
  @visibleForTesting
  static void resetLastSentAt() => _lastSentAt = null;

  /// Overrides the last-sent timestamp. Only for use in tests.
  @visibleForTesting
  static void setLastSentAtForTesting(DateTime value) => _lastSentAt = value;

  /// Sends a fall alert SMS to all contacts.
  ///
  /// [message] is the fully localized message string, built by the caller
  /// using [AppLocalizations] (which has access to BuildContext).
  ///
  /// Returns the list of contact names to which the SMS was sent.
  /// Returns an empty list immediately if called within 60 seconds of the last send.
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  }) async {
    if (contacts.isEmpty) return [];

    final now = DateTime.now();

    // Load persisted timestamp on first call after app restart
    if (_lastSentAt == null) {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kLastSentAtMs);
      if (ms != null) _lastSentAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    if (_lastSentAt != null && now.difference(_lastSentAt!).inSeconds < 60) {
      return [];
    }

    final phones = contacts.map((c) => c.phone).toList();

    try {
      final result = await sendSMS(message: message, recipients: phones);
      if (result == 'sent') {
        _lastSentAt = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kLastSentAtMs, _lastSentAt!.millisecondsSinceEpoch);
        return contacts.map((c) => c.name).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
