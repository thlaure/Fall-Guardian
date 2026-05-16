import 'package:caregiver_app/services/pending_alert_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PendingAlertStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = PendingAlertStore();
  });

  test('save and take returns a pending fall alert once', () async {
    await store.save({
      'alertId': 'alert-1',
      'fallTimestamp': '2026-05-16T08:30:00+00:00',
      'latitude': '48.8566',
      'longitude': '2.3522',
    });

    final alert = await store.take();

    expect(alert?['alertId'], 'alert-1');
    expect(alert?['fallTimestamp'], '2026-05-16T08:30:00+00:00');
    expect(await store.take(), isNull);
  });

  test('save ignores messages that are not fall alerts', () async {
    await store.save({'kind': 'token-refresh'});

    expect(await store.take(), isNull);
  });
}
