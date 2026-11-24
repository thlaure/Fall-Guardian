import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret "this install has registered with the backend" marker.
///
/// Credentials live in secure storage (Android Keystore-encrypted prefs, iOS
/// Keychain); this marker lives in plain app preferences. The two stores have
/// different lifetimes, which is exactly what lets us tell a first launch
/// from lost credentials:
///
/// - Fresh install (both platforms): no marker, no credentials → register.
/// - iOS reinstall: UserDefaults are wiped but the Keychain survives →
///   credentials found, marker re-created (migration path below).
/// - Android Keystore invalidated / iOS Keychain reset while the app stays
///   installed: marker present, credentials gone → re-pairing required,
///   never a silent orphan registration.
/// - Android reinstall: both are wiped (allowBackup=false) → fresh install.
abstract class DeviceRegistrationMarker {
  Future<bool> isSet();

  Future<void> set();
}

class SharedPreferencesRegistrationMarker implements DeviceRegistrationMarker {
  const SharedPreferencesRegistrationMarker();

  static const key = 'backend_device_registered';

  @override
  Future<bool> isSet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (error, stackTrace) {
      // Unreadable preferences must not block the very first registration;
      // this degrades to the previous behaviour.
      developer.log(
        'Registration marker unreadable',
        name: 'DeviceRegistrationMarker',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> set() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (error, stackTrace) {
      developer.log(
        'Registration marker not persisted',
        name: 'DeviceRegistrationMarker',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
