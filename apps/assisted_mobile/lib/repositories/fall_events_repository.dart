import 'dart:convert';
import '../models/fall_event.dart';
import '../services/alert_ports.dart';
import '../services/secure_store.dart';
import 'shared_preferences_migration.dart';

class FallEventsRepository implements FallEventRecorder {
  FallEventsRepository({KeyValueStore? store})
      : _store = store ?? SecureKeyValueStore();

  static const _key = 'fall_events';
  final KeyValueStore _store;

  Future<List<FallEvent>> getAll() async {
    final raw = await _readRaw();
    final eventsByTimestamp = <int, FallEvent>{};
    for (final s in raw) {
      try {
        final event = FallEvent.fromJson(
          jsonDecode(s) as Map<String, dynamic>,
        );
        final key = event.timestamp.millisecondsSinceEpoch;
        final existing = eventsByTimestamp[key];
        if (existing == null ||
            _outcomePriority(event.status) >
                _outcomePriority(existing.status)) {
          eventsByTimestamp[key] = event;
        }
      } catch (_) {
        // skip corrupted entry
      }
    }
    final events = eventsByTimestamp.values.toList();
    return events..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  int _outcomePriority(FallEventStatus status) => switch (status) {
        FallEventStatus.cancelled => 4,
        FallEventStatus.cancellationPending => 3,
        FallEventStatus.alertSent => 2,
        FallEventStatus.alertFailed || FallEventStatus.timedOutNoSms => 1,
      };

  @override
  Future<void> add(FallEvent event) async {
    final raw = await _readRaw();
    // One fall must have one final local outcome. Async registration,
    // timeout, and cancellation callbacks can race; replace an earlier
    // provisional outcome instead of displaying contradictory history rows.
    raw.removeWhere((encoded) {
      try {
        final existing = FallEvent.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
        return existing.timestamp.isAtSameMomentAs(event.timestamp);
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(event.toJson()));
    await _store.write(_key, jsonEncode(raw));
    await deleteLegacyKey(_key);
  }

  Future<void> clear() async {
    await _store.delete(_key);
    await deleteLegacyKey(_key);
  }

  Future<List<String>> _readRaw() async {
    final secureRaw = await _store.read(_key);
    if (secureRaw != null) {
      try {
        final decoded = jsonDecode(secureRaw) as List<dynamic>;
        return List<String>.from(decoded);
      } catch (_) {
        await _store.delete(_key);
      }
    }

    final legacyRaw = List<String>.from(await readLegacyStringList(_key));
    if (legacyRaw.isNotEmpty) {
      await _store.write(_key, jsonEncode(legacyRaw));
      await deleteLegacyKey(_key);
    }
    return legacyRaw;
  }
}
