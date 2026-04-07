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
    final events = <FallEvent>[];
    for (final s in raw) {
      try {
        events.add(FallEvent.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // skip corrupted entry
      }
    }
    return events..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<void> add(FallEvent event) async {
    final raw = await _readRaw();
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
