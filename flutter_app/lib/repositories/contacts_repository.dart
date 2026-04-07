import 'dart:convert';
import '../models/contact.dart';
import '../services/alert_ports.dart';
import '../services/secure_store.dart';
import 'shared_preferences_migration.dart';

class ContactsRepository implements EmergencyContactsStore {
  ContactsRepository({KeyValueStore? store})
      : _store = store ?? SecureKeyValueStore();

  static const _key = 'contacts';
  final KeyValueStore _store;

  @override
  Future<List<Contact>> getAll() async {
    final raw = await _readRaw();
    final contacts = <Contact>[];
    for (final s in raw) {
      try {
        contacts.add(Contact.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // skip corrupted entry
      }
    }
    return contacts;
  }

  Future<void> save(List<Contact> contacts) async {
    await _store.write(
      _key,
      jsonEncode(contacts.map((c) => jsonEncode(c.toJson())).toList()),
    );
    await deleteLegacyKey(_key);
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

    final legacyRaw = await readLegacyStringList(_key);
    if (legacyRaw.isNotEmpty) {
      await _store.write(_key, jsonEncode(legacyRaw));
      await deleteLegacyKey(_key);
    }
    return legacyRaw;
  }
}
