import 'dart:convert';

import 'package:caregiver_app/services/pending_alert_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _alert(String id, {String? reminder}) => {
  'type': 'fall_alert',
  'alertId': id,
  'fallTimestamp': '2026-05-16T08:30:00+00:00',
  'reminder': ?reminder,
};

void main() {
  late PendingAlertStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    store = PendingAlertStore();
  });

  test('save and takeAll returns pending fall alerts once', () async {
    await store.save({
      'alertId': 'alert-1',
      'fallTimestamp': '2026-05-16T08:30:00+00:00',
      'latitude': '48.8566',
      'longitude': '2.3522',
    });

    final alerts = await store.takeAll();

    expect(alerts.single['alertId'], 'alert-1');
    expect(alerts.single['latitude'], '48.8566');
    expect(await store.takeAll(), isEmpty);
  });

  test('keeps alerts for several protected persons, oldest first', () async {
    await store.save(_alert('alert-1'));
    await store.save(_alert('alert-2'));
    await store.save(_alert('alert-3'));

    final alerts = await store.takeAll();

    expect(alerts.map((a) => a['alertId']), ['alert-1', 'alert-2', 'alert-3']);
  });

  test(
    'a repeated push for the same alert replaces the earlier entry',
    () async {
      await store.save(_alert('alert-1'));
      await store.save(_alert('alert-2'));
      await store.save(_alert('alert-1', reminder: '1'));

      final alerts = await store.takeAll();

      expect(alerts.map((a) => a['alertId']), ['alert-2', 'alert-1']);
      expect(alerts.last['reminder'], '1');
    },
  );

  test('is bounded and drops the oldest alerts first', () async {
    store = PendingAlertStore(maxAlerts: 2);
    await store.save(_alert('alert-1'));
    await store.save(_alert('alert-2'));
    await store.save(_alert('alert-3'));

    final alerts = await store.takeAll();

    expect(alerts.map((a) => a['alertId']), ['alert-2', 'alert-3']);
  });

  test('remove drops only the given alert', () async {
    await store.save(_alert('alert-1'));
    await store.save(_alert('alert-2'));

    await store.remove('alert-1');
    await store.remove('unknown');

    expect((await store.takeAll()).map((a) => a['alertId']), ['alert-2']);
  });

  test('removing the last alert clears the list', () async {
    await store.save(_alert('alert-1'));

    await store.remove('alert-1');

    expect(await store.takeAll(), isEmpty);
  });

  test('save ignores messages that are not fall alerts', () async {
    await store.save({'kind': 'token-refresh'});
    await store.save({'alertId': 'alert-1'});

    expect(await store.takeAll(), isEmpty);
  });

  test(
    'migrates the legacy secure single entry and keeps it with new alerts',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        PendingAlertStore.legacyKey: jsonEncode(_alert('alert-legacy')),
      });

      await store.save(_alert('alert-new'));
      const storage = FlutterSecureStorage();

      expect(await storage.read(key: PendingAlertStore.legacyKey), isNull);
      expect((await store.takeAll()).map((a) => a['alertId']), [
        'alert-legacy',
        'alert-new',
      ]);
    },
  );

  test(
    'takeAll migrates one pending plaintext alert and deletes legacy storage',
    () async {
      SharedPreferences.setMockInitialValues({
        'pending_fall_alert': '{"alertId":"alert-legacy","fallTimestamp":"2026-05-16T08:30:00+00:00"}',
      });

      final alerts = await store.takeAll();
      final prefs = await SharedPreferences.getInstance();

      expect(alerts.single['alertId'], 'alert-legacy');
      expect(prefs.getString('pending_fall_alert'), isNull);
      expect(await store.takeAll(), isEmpty);
    },
  );

  test('legacy entries duplicating a listed alert are not repeated', () async {
    FlutterSecureStorage.setMockInitialValues({
      PendingAlertStore.legacyKey: jsonEncode(_alert('alert-1')),
      PendingAlertStore.listKey: jsonEncode([_alert('alert-1')]),
    });

    expect(await store.takeAll(), hasLength(1));
  });

  test('corrupted stored data is discarded safely', () async {
    FlutterSecureStorage.setMockInitialValues({
      PendingAlertStore.listKey: 'not json',
      PendingAlertStore.legacyKey: '{broken',
    });
    expect(await store.takeAll(), isEmpty);

    FlutterSecureStorage.setMockInitialValues({
      PendingAlertStore.listKey: jsonEncode({'alertId': 'not-a-list'}),
      PendingAlertStore.legacyKey: jsonEncode(['not-a-map']),
    });
    expect(await store.takeAll(), isEmpty);

    FlutterSecureStorage.setMockInitialValues({
      PendingAlertStore.listKey: jsonEncode([
        'string',
        {'alertId': 'missing-timestamp'},
        _alert('alert-ok'),
      ]),
    });
    expect((await store.takeAll()).single['alertId'], 'alert-ok');
  });
}
