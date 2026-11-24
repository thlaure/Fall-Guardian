import 'dart:convert';

import 'package:caregiver_app/services/caregiver_backend_service.dart';
import 'package:caregiver_app/services/caregiver_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_keychain.dart';

void main() {
  const keys = ['caregiver_device_id', 'caregiver_device_token'];
  const legacyItems = {
    'caregiver_device_id': 'device-1',
    'caregiver_device_token': 'token-1',
  };
  const newClass = 'first_unlock_this_device';
  final marker = SecureStorageAccessibilityMigration.markerKey;

  SecureStorageAccessibilityMigration migration(FakeKeychain keychain) =>
      SecureStorageAccessibilityMigration(keys: keys, storage: keychain);

  test('rewrites legacy items with the locked-readable class', () async {
    final keychain = FakeKeychain(legacyItems);

    expect(await migration(keychain).run(), isTrue);

    for (final key in keys) {
      expect(keychain.items[key]?.$1, legacyItems[key]);
      expect(keychain.accessibilityOf(key), newClass);
      expect(
        keychain.items.containsKey(
          SecureStorageAccessibilityMigration.backupKeyFor(key),
        ),
        isFalse,
      );
    }
    expect(keychain.items[marker]?.$1, '1');

    // The regression: credentials must stay readable while the phone is locked.
    keychain.locked = true;
    expect(
      await keychain.read(key: 'caregiver_device_token'),
      legacyItems['caregiver_device_token'],
    );
  });

  test('runs only once thanks to the version marker', () async {
    final keychain = FakeKeychain(legacyItems);
    await migration(keychain).run();
    keychain.items['caregiver_device_id'] = ('device-1', 'unlocked');

    expect(await migration(keychain).run(), isTrue);

    expect(keychain.accessibilityOf('caregiver_device_id'), 'unlocked');
  });

  test('restores the legacy item when the re-add fails after delete', () async {
    final keychain = FakeKeychain(legacyItems)
      ..failAddAfterDelete.add('caregiver_device_token');

    expect(await migration(keychain).run(), isFalse);

    expect(keychain.items['caregiver_device_token'], ('token-1', 'unlocked'));
    expect(
      keychain
          .items[SecureStorageAccessibilityMigration.backupKeyFor(
            'caregiver_device_token',
          )]
          ?.$1,
      'token-1',
    );
    expect(keychain.items.containsKey(marker), isFalse);
    // Other keys are still migrated.
    expect(keychain.accessibilityOf('caregiver_device_id'), newClass);

    keychain.failAddAfterDelete.clear();
    expect(await migration(keychain).run(), isTrue);
    expect(keychain.items['caregiver_device_token'], ('token-1', newClass));
    expect(keychain.items.keys, isNot(contains(endsWith('migration_backup'))));
  });

  test('resumes an interrupted migration from the backup copy', () async {
    // App killed after the plugin deleted the item but before it re-added it.
    final keychain = FakeKeychain({
      'caregiver_device_id': 'device-1',
      SecureStorageAccessibilityMigration.backupKeyFor(
        'caregiver_device_token',
      ): 'token-1',
    });

    expect(await migration(keychain).run(), isTrue);

    expect(keychain.items['caregiver_device_token'], ('token-1', newClass));
  });

  test('keeps the backup when the rewritten value does not verify', () async {
    final keychain = FakeKeychain(legacyItems)
      ..corruptReadsAfterWrite.add('caregiver_device_id');

    expect(await migration(keychain).run(), isFalse);

    expect(
      keychain
          .items[SecureStorageAccessibilityMigration.backupKeyFor(
            'caregiver_device_id',
          )]
          ?.$1,
      'device-1',
    );
    expect(keychain.items.containsKey(marker), isFalse);
  });

  test('does nothing when disabled (Android)', () async {
    final keychain = FakeKeychain(legacyItems);

    expect(
      await SecureStorageAccessibilityMigration(
        keys: keys,
        storage: keychain,
        enabled: false,
      ).run(),
      isTrue,
    );

    expect(keychain.accessibilityOf('caregiver_device_id'), 'unlocked');
    expect(keychain.items.containsKey(marker), isFalse);
  });

  test('a fresh install without items only writes the marker', () async {
    final keychain = FakeKeychain();

    expect(await migration(keychain).run(), isTrue);

    expect(keychain.items.keys, [marker]);
  });

  test(
    'aborts without touching items when the keychain is unreadable',
    () async {
      final keychain = FakeKeychain({...legacyItems, marker: '0'})
        ..locked = true;

      expect(await migration(keychain).run(), isFalse);

      expect(keychain.accessibilityOf('caregiver_device_token'), 'unlocked');
    },
  );

  test('a failed read of one item leaves it untouched', () async {
    final keychain = FakeKeychain(legacyItems);
    keychain.items[marker] = ('0', newClass);
    keychain.locked = true;

    expect(await migration(keychain).run(), isFalse);

    expect(keychain.items['caregiver_device_token'], ('token-1', 'unlocked'));
  });

  test('backend migration keeps credentials so locked receipts need no re-registration', () async {
    final keychain = FakeKeychain({...legacyItems, 'caregiver_linked': 'true'});
    final requests = <http.Request>[];
    final service = CaregiverBackendService(
      baseUrl: 'http://api.test',
      storage: keychain,
      isIOSPlatform: true,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({}), 202);
      }),
    );

    expect(await service.migrateSecureStorage(), isTrue);
    expect(keychain.accessibilityOf('caregiver_linked'), newClass);

    keychain.locked = true;
    await service.reportAlertReceived('alert-1');

    expect(requests.single.url.path, '/api/v1/fall-alerts/alert-1/receipt');
    expect(requests.single.headers['Authorization'], 'Bearer token-1');
    expect(await service.isLinked(), isTrue);
  });

  test('backend migration is skipped on Android', () async {
    final keychain = FakeKeychain(legacyItems);
    final service = CaregiverBackendService(
      baseUrl: 'http://api.test',
      storage: keychain,
      isIOSPlatform: false,
    );

    expect(await service.migrateSecureStorage(), isTrue);
    expect(keychain.accessibilityOf('caregiver_device_id'), 'unlocked');
  });
}
