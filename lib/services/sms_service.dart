import 'package:flutter_sms/flutter_sms.dart';
import '../models/contact.dart';

class SmsService {
  /// Sends a fall alert SMS to all contacts.
  /// Returns list of contact names successfully notified.
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required double? latitude,
    required double? longitude,
  }) async {
    if (contacts.isEmpty) return [];

    final locationText = (latitude != null && longitude != null)
        ? '\nLocation: https://maps.google.com/?q=$latitude,$longitude'
        : '\nLocation: unavailable';

    final message =
        '🚨 FALL ALERT: Your loved one may have fallen and needs help.'
        '$locationText\n'
        'Please call or go check on them immediately.\n'
        '– Fall Guardian App';

    final phones = contacts.map((c) => c.phone).toList();

    try {
      final result = await sendSMS(message: message, recipients: phones);
      // flutter_sms returns 'sent' or 'cancelled'
      if (result == 'sent') {
        return contacts.map((c) => c.name).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
