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

/// A keychain item exists but cannot be read right now (iPhone locked and
/// the item is in a class that requires the device to be unlocked).
class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException(this.key, [this.cause]);

  final String key;
  final Object? cause;

  @override
  String toString() => 'SecureStorageUnavailableException($key)';
}

/// Reads [key], distinguishing "absent" from "present but unreadable".
///
/// On iOS, flutter_secure_storage 9.x `read()` returns null (not an error)
/// for an item that exists but is locked: its first query fails with
/// errSecInteractionNotAllowed and its synchronizable fallback query then
/// reports "not found". Treating that null as "absent" would make the app
/// register a new device and silently unlink the caregiver. `containsKey`
/// only queries attributes, so it either finds the item or surfaces the
/// keychain error; both mean the value must not be treated as missing.
Future<String?> readExistingSecureValue(
  FlutterSecureStorage storage,
  String key, {
  IOSOptions? iOptions,
}) async {
  final value = await storage.read(key: key, iOptions: iOptions);
  if (value != null) return value;

  final bool exists;
  try {
    exists = await storage.containsKey(key: key, iOptions: iOptions);
  } catch (error) {
    throw SecureStorageUnavailableException(key, error);
  }
  if (exists) throw SecureStorageUnavailableException(key);
  return null;
}

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

  /// Returns true when all items use the new accessibility class. Returns
  /// false (and changes nothing) when protected data is unavailable, so the
  /// caller retries on the next foreground resume.
  Future<bool> run() async {
    if (!enabled) return true;

    try {
      // Null on platforms/mocks without the API: rely on the read checks.
      if (await _storage.isCupertinoProtectedDataAvailable() == false) {
        developer.log(
          'Keychain migration deferred: protected data unavailable',
          name: 'SecureStorageAccessibilityMigration',
        );
        return false;
      }
      final marker = await readExistingSecureValue(
        _storage,
        markerKey,
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
      final result = await _migrateKey(key);
      if (result == _KeyMigration.unavailable) {
        // The keychain is locked: stop now, retry the whole run later.
        return false;
      }
      if (result == _KeyMigration.failed) {
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

  Future<_KeyMigration> _migrateKey(String key) async {
    final backupKey = backupKeyFor(key);
    String? value;
    try {
      // The plugin's read ignores accessibility, so legacy items are found.
      // A locked item throws instead of looking absent.
      value = await readExistingSecureValue(
        _storage,
        key,
        iOptions: legacyIOSOptions,
      );
      // A backup only exists if a previous run was interrupted between the
      // plugin's delete and re-add of the item: restore from it.
      value ??= await readExistingSecureValue(
        _storage,
        backupKey,
        iOptions: legacyIOSOptions,
      );
      if (value == null) return _KeyMigration.done;
    } on SecureStorageUnavailableException catch (error) {
      developer.log(
        'Keychain migration deferred: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
      return _KeyMigration.unavailable;
    } catch (error) {
      developer.log(
        'Keychain migration read failed: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
      return _KeyMigration.failed;
    }

    try {
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
      return _KeyMigration.done;
    } catch (error) {
      developer.log(
        'Keychain migration failed for one item: $error',
        name: 'SecureStorageAccessibilityMigration',
      );
      await _restore(key, value);
      return _KeyMigration.failed;
    }
  }

  /// Puts the value back with the legacy class if the rewrite removed it.
  /// The backup key is intentionally kept for the next attempt.
  Future<void> _restore(String key, String value) async {
    try {
      final current = await readExistingSecureValue(
        _storage,
        key,
        iOptions: legacyIOSOptions,
      );
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

enum _KeyMigration { done, failed, unavailable }
