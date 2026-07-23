import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/repositories/fall_events_repository.dart';
import 'package:fall_guardian/services/secure_store.dart';

class _FakeStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  late FallEventsRepository repo;
  late _FakeStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FakeStore();
    repo = FallEventsRepository(store: store);
  });

  group('FallEventsRepository', () {
    test('getAll returns empty list initially', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('add persists an event', () async {
      final event = FallEvent(
        id: '1',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.alertSent,
        notifiedContacts: ['Alice'],
      );
      await repo.add(event);
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.id, '1');
    });

    test('add replaces a provisional outcome for the same fall', () async {
      final timestamp = DateTime.utc(2026, 7, 23, 9, 55, 7);
      await repo.add(
        FallEvent(
          id: 'provisional',
          timestamp: timestamp,
          status: FallEventStatus.alertSent,
        ),
      );
      await repo.add(
        FallEvent(
          id: 'final',
          timestamp: timestamp,
          status: FallEventStatus.cancelled,
        ),
      );

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, 'final');
      expect(all.single.status, FallEventStatus.cancelled);
    });

    test('getAll repairs contradictory legacy outcomes for the same fall',
        () async {
      final timestamp = DateTime.utc(2026, 7, 23, 9, 55, 7);
      final cancelled = FallEvent(
        id: 'cancelled',
        timestamp: timestamp,
        status: FallEventStatus.cancelled,
      );
      final falseAlertSent = FallEvent(
        id: 'false-alert-sent',
        timestamp: timestamp,
        status: FallEventStatus.alertSent,
      );
      store.data['fall_events'] = jsonEncode([
        jsonEncode(cancelled.toJson()),
        jsonEncode(falseAlertSent.toJson()),
      ]);

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, 'cancelled');
      expect(all.single.status, FallEventStatus.cancelled);
    });

    test('getAll returns events sorted newest first', () async {
      final older = FallEvent(
        id: 'old',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.cancelled,
      );
      final newer = FallEvent(
        id: 'new',
        timestamp: DateTime(2024, 6, 1),
        status: FallEventStatus.alertSent,
      );
      await repo.add(older);
      await repo.add(newer);
      final all = await repo.getAll();
      expect(all.first.id, 'new');
      expect(all.last.id, 'old');
    });

    test('clear removes all events', () async {
      await repo.add(
        FallEvent(
          id: '1',
          timestamp: DateTime(2024, 1, 1),
          status: FallEventStatus.cancelled,
        ),
      );
      await repo.clear();
      expect(await repo.getAll(), isEmpty);
    });

    test('add preserves location and contacts', () async {
      final event = FallEvent(
        id: '1',
        timestamp: DateTime(2024, 1, 1),
        status: FallEventStatus.alertSent,
        latitude: 48.8566,
        longitude: 2.3522,
        notifiedContacts: ['Alice', 'Bob'],
      );
      await repo.add(event);
      final restored = (await repo.getAll()).first;
      expect(restored.latitude, 48.8566);
      expect(restored.longitude, 2.3522);
      expect(restored.notifiedContacts, ['Alice', 'Bob']);
    });

    test('getAll_skipsCorruptedJsonEntries', () async {
      // Build a valid event JSON string.
      final validEvent = FallEvent(
        id: 'valid-1',
        timestamp: DateTime(2024, 3, 1),
        status: FallEventStatus.cancelled,
      );
      final validJson = jsonEncode(validEvent.toJson());

      // Inject one corrupted and one valid entry directly into SharedPreferences.
      SharedPreferences.setMockInitialValues({
        'fall_events': ['invalid json{{{', validJson],
      });
      repo = FallEventsRepository(store: store);

      final all = await repo.getAll();
      expect(all.length, 1, reason: 'Corrupted entry must be silently skipped');
      expect(all.first.id, 'valid-1');
    });

    test('getAll deletes and recovers from a corrupted secure store value',
        () async {
      store.data['fall_events'] = 'not a valid json list';

      final all = await repo.getAll();

      expect(all, isEmpty);
      expect(store.data.containsKey('fall_events'), isFalse);
    });

    test('clear_isIdempotent', () async {
      await repo.add(
        FallEvent(
          id: '1',
          timestamp: DateTime(2024, 1, 1),
          status: FallEventStatus.cancelled,
        ),
      );
      await repo.clear();
      // Second clear on an already-empty repository must not throw.
      await repo.clear();
      expect(await repo.getAll(), isEmpty);
    });

    test('getAll migrates legacy shared preferences into secure storage',
        () async {
      final validEvent = FallEvent(
        id: 'valid-1',
        timestamp: DateTime(2024, 3, 1),
        status: FallEventStatus.cancelled,
      );
      final validJson = jsonEncode(validEvent.toJson());
      SharedPreferences.setMockInitialValues({
        'fall_events': [validJson],
      });
      repo = FallEventsRepository(store: store);

      final all = await repo.getAll();

      expect(all.single.id, 'valid-1');
      expect(store.data['fall_events'], contains('valid-1'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('fall_events'), isNull);
    });
  });
}
