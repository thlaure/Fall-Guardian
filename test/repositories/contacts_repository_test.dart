import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fall_guardian/models/contact.dart';
import 'package:fall_guardian/repositories/contacts_repository.dart';
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
  late ContactsRepository repo;
  late _FakeStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FakeStore();
    repo = ContactsRepository(store: store);
  });

  group('ContactsRepository', () {
    test('getAll returns empty list initially', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('add persists a contact', () async {
      const c = Contact(id: '1', name: 'Alice', phone: '+33600000000');
      await repo.add(c);
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'Alice');
    });

    test('add multiple contacts', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.add(const Contact(id: '2', name: 'Bob', phone: '+2'));
      expect((await repo.getAll()).length, 2);
    });

    test('remove deletes by id', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.add(const Contact(id: '2', name: 'Bob', phone: '+2'));
      await repo.remove('1');
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.id, '2');
    });

    test('remove with unknown id does nothing', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.remove('unknown');
      expect((await repo.getAll()).length, 1);
    });

    test('update replaces contact with matching id', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.update(
        const Contact(id: '1', name: 'Alice Updated', phone: '+2'),
      );
      final all = await repo.getAll();
      expect(all.first.name, 'Alice Updated');
      expect(all.first.phone, '+2');
    });

    test('update with unknown id does nothing', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.update(const Contact(id: '99', name: 'Ghost', phone: '+0'));
      expect((await repo.getAll()).length, 1);
      expect((await repo.getAll()).first.name, 'Alice');
    });

    test('save replaces all contacts', () async {
      await repo.add(const Contact(id: '1', name: 'Alice', phone: '+1'));
      await repo.save([const Contact(id: '2', name: 'Bob', phone: '+2')]);
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'Bob');
    });

    test('getAll_skipsCorruptedJsonEntries', () async {
      const validContact = Contact(id: '42', name: 'Alice', phone: '+1');
      final validJson = jsonEncode(validContact.toJson());

      // Inject corrupted + valid entries directly into SharedPreferences.
      SharedPreferences.setMockInitialValues({
        'contacts': ['not valid json!!!', validJson],
      });
      repo = ContactsRepository(store: store);

      final all = await repo.getAll();
      expect(all.length, 1, reason: 'Corrupted entry must be silently skipped');
      expect(all.first.id, '42');
    });

    test('getAll migrates legacy shared preferences into secure storage',
        () async {
      const validContact = Contact(id: '42', name: 'Alice', phone: '+1');
      final validJson = jsonEncode(validContact.toJson());
      SharedPreferences.setMockInitialValues({
        'contacts': [validJson],
      });
      repo = ContactsRepository(store: store);

      final all = await repo.getAll();

      expect(all.single.id, '42');
      expect(store.data['contacts'], contains('Alice'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('contacts'), isNull);
    });
  });
}
