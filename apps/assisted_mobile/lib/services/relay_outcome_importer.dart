import 'dart:developer' as developer;

import '../models/fall_event.dart';
import 'alert_ports.dart';
import 'watch_communication_service.dart';

/// Imports terminal results of the native relays (which may have run while
/// Flutter was not alive) into the local fall history, so a permanently
/// rejected or late-cancelled incident is never silently lost.
class RelayOutcomeImporter {
  RelayOutcomeImporter({
    required FallEventRecorder recorder,
    required IdGenerator idGenerator,
    Future<List<RelayOutcomeRecord>> Function()? takeOutcomes,
  })  : _recorder = recorder,
        _idGenerator = idGenerator,
        _takeOutcomes =
            takeOutcomes ?? WatchCommunicationService.takeRelayOutcomes;

  final FallEventRecorder _recorder;
  final IdGenerator _idGenerator;
  final Future<List<RelayOutcomeRecord>> Function() _takeOutcomes;

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

    var written = 0;
    for (final outcome in outcomes) {
      final status = statusFor(outcome.outcome);
      if (status == null) continue;
      await _recorder.add(FallEvent(
        id: _idGenerator.newId(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          outcome.fallTimestamp,
          isUtc: true,
        ),
        status: status,
      ));
      written++;
    }
    return written;
  }

  /// Never-delivered incidents are failures; a cancellation the server
  /// refused means caregivers were (or may have been) notified.
  static FallEventStatus? statusFor(String outcome) => switch (outcome) {
        'create_rejected' || 'dropped' => FallEventStatus.alertFailed,
        'cancel_too_late' || 'cancel_rejected' => FallEventStatus.alertSent,
        _ => null,
      };
}
