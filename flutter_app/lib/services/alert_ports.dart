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

abstract class AlertSmsGateway {
  Future<List<String>> sendFallAlert({
    required List<Contact> contacts,
    required String message,
  });
}

abstract class WatchCommandGateway {
  Future<void> sendCancelAlert();
}

abstract class AlertLocaleResolver {
  AppLocalizations resolve();
}

abstract class Clock {
  DateTime now();
}

abstract class IdGenerator {
  String newId();
}
