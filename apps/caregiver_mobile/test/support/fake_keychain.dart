import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory model of the iOS keychain as used by flutter_secure_storage 9.x.
///
/// Mirrors the plugin's native behavior that matters for migrations:
/// - `read` ignores accessibility (an item is found whatever its class);
/// - `write` with a different accessibility deletes the item, then re-adds it;
/// - while [locked], reading an item in the `unlocked` class returns null
///   WITHOUT an error (the plugin's errSecInteractionNotAllowed is masked by
///   its synchronizable fallback query), exactly like iOS;
/// - `containsKey` queries attributes only, so it still finds locked items
///   (or throws when [containsKeyThrows] simulates a keychain error);
/// - `isCupertinoProtectedDataAvailable` reports `!locked`.
class FakeKeychain extends FlutterSecureStorage {
  FakeKeychain([Map<String, String> unlockedItems = const {}]) : super() {
    unlockedItems.forEach((key, value) => items[key] = (value, 'unlocked'));
  }

  final Map<String, (String, String)> items = {};
  bool locked = false;
  bool containsKeyThrows = false;

  /// Simulates platforms/mocks where protected-data state is unknown (null),
  /// so only the read/containsKey checks protect the migration.
  bool protectedDataStateUnknown = false;

  /// Keys whose re-add fails after the plugin already deleted the old item.
  final Set<String> failAddAfterDelete = {};

  /// Keys whose read-back returns a corrupted value.
  final Set<String> corruptReadsAfterWrite = {};
  final Set<String> _written = {};

  String? accessibilityOf(String key) => items[key]?.$2;

  static String _accessibility(IOSOptions? options) =>
      options?.toMap()['accessibility'] ?? 'unlocked';

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final item = items[key];
    if (item == null) return null;
    if (locked && item.$2 == 'unlocked') {
      return null;
    }
    if (_written.contains(key) && corruptReadsAfterWrite.contains(key)) {
      return '${item.$1}-corrupted';
    }
    return item.$1;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      items.remove(key);
      return;
    }
    final accessibility = _accessibility(iOptions);
    final existing = items[key];
    if (existing != null && existing.$2 != accessibility) {
      items.remove(key);
      if (failAddAfterDelete.contains(key)) {
        throw PlatformException(code: '-25299', message: 'Add failed');
      }
    }
    items[key] = (value, accessibility);
    _written.add(key);
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    items.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (containsKeyThrows) {
      throw PlatformException(
        code: '-25308',
        message: 'Interaction not allowed',
      );
    }
    return items.containsKey(key);
  }

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() async =>
      protectedDataStateUnknown ? null : !locked;
}
