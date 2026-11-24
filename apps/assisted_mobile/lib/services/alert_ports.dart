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

/// What the API told us when it accepted a fall alert.
///
/// The backend owns the cancellation window. [remainingGrace] is how long is
/// left before the server dispatches caregiver pushes, measured on the
/// server's own clock (cancelDeadlineAt minus the server time of the
/// response) and already reduced by the request round trip. The caller
/// anchors it on its monotonic clock, so phone/watch clock skew cannot move
/// the displayed deadline.
class FallAlertReceipt {
  const FallAlertReceipt({required this.remainingGrace});

  final Duration remainingGrace;
}

abstract class AlertBackendGateway {
  Future<void> ensureReady();

  Future<void> syncContacts(List<Contact> contacts);

  /// Returns null when the API response does not carry deadline data.
  Future<FallAlertReceipt?> submitFallAlert({
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
  /// [incidentId]/[fallTimestamp] let newer watches cancel only the matching
  /// incident; older watches ignore them.
  Future<void> sendCancelAlert({String? incidentId, int? fallTimestamp});
}

/// Durable, process-independent storage of incidents that still need backend
/// delivery. Implemented by the native relay queue (Android JobScheduler /
/// iOS BGTaskScheduler), which retries even after the app process dies.
abstract class DurableAlertQueue {
  Future<void> enqueue({
    required String clientAlertId,
    required int fallTimestamp,
  });
}

abstract class AlertLocaleResolver {
  AppLocalizations resolve();

  String languageCode();
}

abstract class Clock {
  DateTime now();

  /// Monotonic elapsed time used for durations. Unlike wall time, this cannot
  /// jump when network time or user settings change.
  Duration elapsed();
}

abstract class IdGenerator {
  String newId();
}
