import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import '../models/contact.dart';
import '../models/fall_event.dart';

/// Small ports that keep the alert workflow independent from storage,
/// platform APIs, and concrete plugins.
abstract class EmergencyContactsStore {
  Future<List<Contact>> getAll();
}

abstract class FallEventRecorder {
  Future<void> add(FallEvent event);
}

abstract class AlertLocationProvider {
  Future<Position?> getCurrentPosition();
}

abstract class AlertNotificationGateway {
  Future<void> cancelAll();
}

abstract class AlertBackendGateway {
  Future<void> ensureReady();

  Future<void> syncContacts(List<Contact> contacts);

  Future<void> submitFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  });

  Future<void> recordCancelledFallAlert({
    required String clientAlertId,
    required int fallTimestamp,
    required String locale,
    required double? latitude,
    required double? longitude,
  });

  Future<void> cancelFallAlert({required String clientAlertId});

  /// Best-effort location attachment for an already-submitted alert. Called
  /// once a GPS fix resolves; submitFallAlert must never block on this.
  Future<void> attachLocation({
    required String clientAlertId,
    required double latitude,
    required double longitude,
  });
}

abstract class WatchCommandGateway {
  Future<void> sendCancelAlert();
}

abstract class AlertLocaleResolver {
  AppLocalizations resolve();

  String languageCode();
}

abstract class Clock {
  DateTime now();
}

abstract class IdGenerator {
  String newId();
}
