import 'package:shared_preferences/shared_preferences.dart';

Future<List<String>> readLegacyStringList(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(key) ?? const [];
}

Future<void> deleteLegacyKey(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
}
