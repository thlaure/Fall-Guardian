import 'package:fall_guardian/models/fall_event.dart';
import 'package:fall_guardian/services/alert_ports.dart';
import 'package:fall_guardian/services/relay_outcome_importer.dart';
import 'package:fall_guardian/services/watch_communication_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder implements FallEventRecorder {
  final events = <FallEvent>[];

  @override
  Future<void> add(FallEvent event) async => events.add(event);
}

class _Ids implements IdGenerator {
  var _next = 0;

  @override
  String newId() => 'event-${_next++}';
}

void main() {
  test('native relay outcomes become history entries', () async {
    final recorder = _Recorder();
    final importer = RelayOutcomeImporter(
      recorder: recorder,
      idGenerator: _Ids(),
      takeOutcomes: () async => const [
        RelayOutcomeRecord(
          clientAlertId: 'a',
          fallTimestamp: 1000,
          outcome: 'create_rejected',
        ),
        RelayOutcomeRecord(
          clientAlertId: 'b',
          fallTimestamp: 2000,
          outcome: 'cancel_too_late',
        ),
        RelayOutcomeRecord(
          clientAlertId: 'c',
          fallTimestamp: 3000,
          outcome: 'something_new',
        ),
      ],
    );

    expect(await importer.importOutcomes(), 2);
    expect(recorder.events.map((e) => e.status), [
      FallEventStatus.alertFailed,
      FallEventStatus.alertSent,
    ]);
    expect(
      recorder.events.first.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
  });

  test('outcome mapping is explicit', () {
    expect(RelayOutcomeImporter.statusFor('create_rejected'),
        FallEventStatus.alertFailed);
    expect(
        RelayOutcomeImporter.statusFor('dropped'), FallEventStatus.alertFailed);
    expect(RelayOutcomeImporter.statusFor('cancel_too_late'),
        FallEventStatus.alertSent);
    expect(RelayOutcomeImporter.statusFor('cancel_rejected'),
        FallEventStatus.alertSent);
    expect(RelayOutcomeImporter.statusFor('unknown'), isNull);
  });

  test('platform failure imports nothing and does not throw', () async {
    final recorder = _Recorder();
    final importer = RelayOutcomeImporter(
      recorder: recorder,
      idGenerator: _Ids(),
      takeOutcomes: () async => throw Exception('no native relay'),
    );

    expect(await importer.importOutcomes(), 0);
    expect(recorder.events, isEmpty);
  });
}
