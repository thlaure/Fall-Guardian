import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';

class ContactsRepository {
  static const _key = 'contacts';

  Future<List<Contact>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => Contact.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      contacts.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<void> add(Contact contact) async {
    final contacts = await getAll();
    contacts.add(contact);
    await save(contacts);
  }

  Future<void> remove(String id) async {
    final contacts = await getAll();
    contacts.removeWhere((c) => c.id == id);
    await save(contacts);
  }

  Future<void> update(Contact updated) async {
    final contacts = await getAll();
    final idx = contacts.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      contacts[idx] = updated;
      await save(contacts);
    }
  }
}
