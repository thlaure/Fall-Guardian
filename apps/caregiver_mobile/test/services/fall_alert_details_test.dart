import 'package:caregiver_app/services/fall_alert_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a current FCM payload without the new optional keys', () {
    final alert = FallAlertDetails.fromData(const {
      'type': 'fall_alert',
      'alertId': 'alert-1',
      'fallTimestamp': '2026-06-16T19:50:03+00:00',
      'latitude': '48.8566',
      'longitude': '2.3522',
    });

    expect(alert.alertId, 'alert-1');
    expect(alert.fallDetectedAt, DateTime.utc(2026, 6, 16, 19, 50, 3));
    expect(alert.latitude, 48.8566);
    expect(alert.longitude, 2.3522);
    expect(alert.hasLocation, isTrue);
    expect(alert.protectedPersonName, isNull);
    expect(alert.cancelDeadlineAt, isNull);
    expect(alert.isReminder, isFalse);
    expect(alert.acknowledgedByMe, isNull);
    expect(alert.acknowledgementCount, isNull);
    expect(alert.handlingState, AlertHandlingState.none);
  });

  test('parses the new optional keys from push or API values', () {
    final alert = FallAlertDetails.fromData(const {
      'alertId': 'alert-1',
      'fallTimestamp': '2026-06-16T19:50:03Z',
      'protectedPersonName': '  Marie  ',
      'cancelDeadlineAt': '2026-06-16T19:50:33+00:00',
      'reminder': '1',
      'acknowledgedAt': '2026-06-16T19:52:00+00:00',
      'acknowledgedByMe': 'false',
      'acknowledgementCount': '2',
    });

    expect(alert.protectedPersonName, 'Marie');
    expect(alert.cancelDeadlineAt, DateTime.utc(2026, 6, 16, 19, 50, 33));
    expect(alert.isReminder, isTrue);
    expect(alert.acknowledgedAt, DateTime.utc(2026, 6, 16, 19, 52));
    expect(alert.acknowledgedByMe, isFalse);
    expect(alert.acknowledgementCount, 2);
    expect(alert.handlingState, AlertHandlingState.handledByOther);
  });

  test('accepts typed JSON values', () {
    final alert = FallAlertDetails.fromData(const {
      'alertId': 'alert-1',
      'latitude': 48.5,
      'longitude': 2,
      'acknowledgedByMe': true,
      'acknowledgementCount': 1,
    });

    expect(alert.latitude, 48.5);
    expect(alert.longitude, 2.0);
    expect(alert.handlingState, AlertHandlingState.handledByMe);
  });

  test('handling state from acknowledgedAt without count', () {
    expect(
      FallAlertDetails.fromData(const {
        'alertId': 'a',
        'acknowledgedByMe': '0',
        'acknowledgedAt': '2026-06-16T19:52:00Z',
      }).handlingState,
      AlertHandlingState.handledByOther,
    );
    expect(
      FallAlertDetails.fromData(const {'alertId': 'a', 'acknowledgedByMe': '1'})
          .handlingState,
      AlertHandlingState.handledByMe,
    );
    expect(
      FallAlertDetails.fromData(const {
        'alertId': 'a',
        'acknowledgementCount': '0',
      }).handlingState,
      AlertHandlingState.none,
    );
  });

  test('ignores malformed values instead of failing', () {
    final alert = FallAlertDetails.fromData(const {
      'alertId': 42,
      'fallTimestamp': 'yesterday',
      'latitude': 'NaN',
      'longitude': '2.35',
      'protectedPersonName': '   ',
      'reminder': 'yes',
      'acknowledgedByMe': 'maybe',
      'acknowledgementCount': 'many',
    });

    expect(alert.alertId, '42');
    expect(alert.rawFallTimestamp, 'yesterday');
    expect(alert.fallDetectedAt, isNull);
    expect(alert.hasLocation, isFalse);
    expect(alert.protectedPersonName, isNull);
    expect(alert.isReminder, isFalse);
    expect(alert.acknowledgedByMe, isNull);
    expect(alert.acknowledgementCount, isNull);
  });

  test('rejects out-of-range coordinates and missing alert id', () {
    final alert = FallAlertDetails.fromData(const {
      'latitude': '123',
      'longitude': '2.35',
    });

    expect(alert.alertId, '');
    expect(alert.hasLocation, isFalse);
  });

  test('backend status acknowledged means another caregiver responded', () {
    expect(
      FallAlertDetails.fromData(const {
        'alertId': 'a',
        'status': 'acknowledged',
        'acknowledgedByMe': 'false',
      }).handlingState,
      AlertHandlingState.handledByOther,
    );
    expect(
      FallAlertDetails.fromData(const {
        'alertId': 'a',
        'status': 'acknowledged',
        'acknowledgedByMe': 'true',
      }).handlingState,
      AlertHandlingState.handledByMe,
    );
    expect(
      FallAlertDetails.fromData(const {'alertId': 'a', 'status': 'sent'})
          .handlingState,
      AlertHandlingState.none,
    );
  });
}
