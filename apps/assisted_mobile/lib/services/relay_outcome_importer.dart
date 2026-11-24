import 'dart:developer' as developer;

import '../models/fall_event.dart';
import 'alert_ports.dart';
import 'watch_communication_service.dart';

/// Imports terminal results of the native relays (which may have run while
/// Flutter was not alive) into the local fall history, so a permanently
/// rejected or late-cancelled incident is never silently lost.
class RelayOutcomeImporter {
  RelayOutcomeImporter({
    required this._recorder,
    required this._idGenerator,
    Future<List<RelayOutcomeRecord>> Function()? takeOutcomes,
    Future<void> Function(List<String> keys)? acknowledgeOutcomes,
    Future<FallEventStatus?> Function(DateTime fallTimestamp)? existingStatus,
  }) : _existingStatus = existingStatus ?? _noExistingStatus,
       _takeOutcomes =
           takeOutcomes ?? WatchCommunicationService.takeRelayOutcomes,
       _acknowledgeOutcomes =
           acknowledgeOutcomes ??
           WatchCommunicationService.acknowledgeRelayOutcomes;

  final FallEventRecorder _recorder;
  final IdGenerator _idGenerator;
  final Future<List<RelayOutcomeRecord>> Function() _takeOutcomes;
  final Future<void> Function(List<String> keys) _acknowledgeOutcomes;
  final Future<FallEventStatus?> Function(DateTime fallTimestamp)
  _existingStatus;

  static Future<FallEventStatus?> _noExistingStatus(DateTime _) async => null;

  /// Returns how many history entries were written.
  Future<int> importOutcomes() async {
    final List<RelayOutcomeRecord> outcomes;
    try {
      outcomes = await _takeOutcomes();
    } catch (error, stackTrace) {
      developer.log(
        'Native relay outcomes unavailable',
        name: 'RelayOutcomeImporter',
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    }

    // Take-then-acknowledge: an outcome is removed natively only after it
    // was persisted here, so a crash in between re-imports it (history
    // entries are keyed by fall timestamp, so a re-import is idempotent).
    var written = 0;
    final persistedKeys = <String>[];
    try {
      for (final outcome in outcomes) {
        final status = statusFor(outcome.outcome);
        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          outcome.fallTimestamp,
          isUtc: true,
        );
        if (status != null &&
            shouldReplace(status, await _existingStatus(timestamp))) {
          await _recorder.add(
            FallEvent(
              id: _idGenerator.newId(),
              timestamp: timestamp,
              status: status,
            ),
          );
          written++;
        }
        // Unknown kinds (newer native code) carry nothing to show.
        persistedKeys.add(outcome.key);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Persisting relay outcome failed; it will be retried',
        name: 'RelayOutcomeImporter',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _acknowledgeOutcomes(persistedKeys);
    } catch (error, stackTrace) {
      developer.log(
        'Acknowledging relay outcomes failed; they will be re-imported',
        name: 'RelayOutcomeImporter',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return written;
  }

  /// Never-delivered incidents are failures; a cancellation the server
  /// refused means caregivers were (or may have been) notified.
  static FallEventStatus? statusFor(String outcome) => switch (outcome) {
    'create_rejected' ||
    'dropped' ||
    'repair_not_delivered' => FallEventStatus.alertFailed,
    'cancel_too_late' || 'cancel_rejected' => FallEventStatus.alertSent,
    'cancel_unconfirmed' => FallEventStatus.cancellationPending,
    'cancelled_unsent' || 'cancelled' => FallEventStatus.cancelled,
    // Native success: replaces a provisional "failed" entry written while
    // Flutter's own submission had not got through.
    'created' => FallEventStatus.alertSent,
    _ => null,
  };

  /// Native outcomes may arrive after Flutter wrote a provisional entry for
  /// the same fall. They upgrade it but never downgrade a more definitive
  /// one (e.g. a late "created" must not hide a confirmed cancellation).
  static bool shouldReplace(
    FallEventStatus incoming,
    FallEventStatus? existing,
  ) {
    if (existing == null || existing == incoming) return true;
    return switch (incoming) {
      // A confirmed cancellation is definitive.
      FallEventStatus.cancelled => true,
      // "Caregivers notified" beats provisional failure/pending entries,
      // never a confirmed cancellation.
      FallEventStatus.alertSent => existing != FallEventStatus.cancelled,
      // Unconfirmed cancel only replaces non-cancel outcomes.
      FallEventStatus.cancellationPending =>
        existing == FallEventStatus.alertSent ||
            existing == FallEventStatus.alertFailed ||
            existing == FallEventStatus.timedOutNoSms,
      // A failure never overrides a delivered or cancelled incident.
      FallEventStatus.alertFailed || FallEventStatus.timedOutNoSms =>
        existing == FallEventStatus.timedOutNoSms,
    };
  }
}
