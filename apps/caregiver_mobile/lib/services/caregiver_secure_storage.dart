import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// iOS keychain class used for every caregiver secret.
///
/// Fall alert pushes are handled by a background isolate, often while the
/// phone is locked. The plugin default (`unlocked`) makes keychain items
/// unreadable in that state, so the device token could not be read to report
/// alert receipt. `first_unlock_this_device` keeps items readable after the
/// first unlock since boot, and never migrates them to another device.
const caregiverIOSOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

/// Secure storage instance shared by caregiver services.
const caregiverSecureStorage = FlutterSecureStorage(
  iOptions: caregiverIOSOptions,
);

/// Options used before the keychain class was changed. Kept so migration can
/// restore an item exactly as it was if a rewrite fails.
const legacyIOSOptions = IOSOptions();

/// Moves keychain items written with the legacy accessibility class to
/// [caregiverIOSOptions].
///
/// The keychain cannot change an item's accessibility in place: the plugin
/// deletes and re-adds it. To make sure a credential is never lost (losing the
/// device token would silently unlink the caregiver), every value is first
/// copied to a backup key, then rewritten, then verified. The backup is only
/// removed after the rewritten value reads back identically. An interrupted
/// migration is resumed from the backup on the next launch.
///
/// Must run while the app is in the foreground (device unlocked): legacy
/// items are not readable while the phone is locked.
class SecureStorageAccessibilityMigration {
  SecureStorageAccessibilityMigration({
    required this.keys,
    FlutterSecureStorage? storage,
    this.enabled = true,
  }) : _storage = storage ?? caregiverSecureStorage;

  static const markerKey = 'caregiver_keychain_accessibility_version';
  static const _currentVersion = '1';
  static const _backupSuffix = '.migration_backup';

  final List<String> keys;
  final bool enabled;
  final FlutterSecureStorage _storage;

  static String backupKeyFor(String key) => '$key$_backupSuffix';

  /// Returns true when all items use the new accessibility class.
  Future<bool> run() async {
    if (!enabled) return true;

    try {
      final marker = await _storage.read(
        key: markerKey,
        iOptions: caregiverIOSOptions,
      );
      if (marker == _currentVersion) return true;
    } catch (error) {
      developer.log(
        'Keychain migration marker unreadable: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
      return false;
    }

    var allMigrated = true;
    for (final key in keys) {
      if (!await _migrateKey(key)) {
        allMigrated = false;
      }
    }

    if (allMigrated) {
      try {
        await _storage.write(
          key: markerKey,
          value: _currentVersion,
          iOptions: caregiverIOSOptions,
        );
      } catch (error) {
        // Not fatal: the migration is idempotent and will run again.
        developer.log(
          'Keychain migration marker write failed: $error',
          name: 'SecureStorageAccessibilityMigration',
        );
        return false;
      }
    }

    return allMigrated;
  }

  Future<bool> _migrateKey(String key) async {
    final backupKey = backupKeyFor(key);
    String? value;
    try {
      // The plugin's read ignores accessibility, so legacy items are found.
      value = await _storage.read(key: key, iOptions: legacyIOSOptions);
      // A backup only exists if a previous run was interrupted between the
      // plugin's delete and re-add of the item: restore from it.
      value ??= await _storage.read(key: backupKey, iOptions: legacyIOSOptions);
      if (value == null) return true;

      await _storage.write(
        key: backupKey,
        value: value,
        iOptions: caregiverIOSOptions,
      );
      await _storage.write(
        key: key,
        value: value,
        iOptions: caregiverIOSOptions,
      );
      final verified = await _storage.read(
        key: key,
        iOptions: caregiverIOSOptions,
      );
      if (verified != value) {
        throw StateError('Rewritten keychain value does not match');
      }

      await _storage.delete(key: backupKey, iOptions: caregiverIOSOptions);
      return true;
    } catch (error) {
      developer.log(
        'Keychain migration failed for one item: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
      if (value != null) {
        await _restore(key, value);
      }
      return false;
    }
  }

  /// Puts the value back with the legacy class if the rewrite removed it.
  /// The backup key is intentionally kept for the next attempt.
  Future<void> _restore(String key, String value) async {
    try {
      final current = await _storage.read(key: key, iOptions: legacyIOSOptions);
      if (current == value) return;
      await _storage.write(key: key, value: value, iOptions: legacyIOSOptions);
    } catch (error) {
      developer.log(
        'Keychain migration restore failed: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
    }
  }
}
