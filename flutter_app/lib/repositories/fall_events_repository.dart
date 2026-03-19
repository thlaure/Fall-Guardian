import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fall_event.dart';

class FallEventsRepository {
  static const _key = 'fall_events';

  Future<List<FallEvent>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
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

  Future<void> add(FallEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(event.toJson()));
    await prefs.setStringList(_key, raw);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
