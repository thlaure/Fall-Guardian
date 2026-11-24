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
      acknowledgeOutcomes: (_) async {},
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
    expect(
      RelayOutcomeImporter.statusFor('create_rejected'),
      FallEventStatus.alertFailed,
    );
    expect(
      RelayOutcomeImporter.statusFor('dropped'),
      FallEventStatus.alertFailed,
    );
    expect(
      RelayOutcomeImporter.statusFor('cancel_too_late'),
      FallEventStatus.alertSent,
    );
    expect(
      RelayOutcomeImporter.statusFor('cancel_rejected'),
      FallEventStatus.alertSent,
    );
    expect(RelayOutcomeImporter.statusFor('unknown'), isNull);
  });

  test('platform failure imports nothing and does not throw', () async {
    final recorder = _Recorder();
    final importer = RelayOutcomeImporter(
      recorder: recorder,
      idGenerator: _Ids(),
      takeOutcomes: () async => throw Exception('no native relay'),
      acknowledgeOutcomes: (_) async {},
    );

    expect(await importer.importOutcomes(), 0);
    expect(recorder.events, isEmpty);
  });
  test('outcomes are acknowledged only after they were persisted', () async {
    final acked = <String>[];
    final importer = RelayOutcomeImporter(
      recorder: _FailingRecorder(failOnCall: 2),
      idGenerator: _Ids(),
      takeOutcomes: () async => const [
        RelayOutcomeRecord(
          clientAlertId: 'a',
          fallTimestamp: 1,
          outcome: 'dropped',
        ),
        RelayOutcomeRecord(
          clientAlertId: 'b',
          fallTimestamp: 2,
          outcome: 'dropped',
        ),
        RelayOutcomeRecord(
          clientAlertId: 'c',
          fallTimestamp: 3,
          outcome: 'dropped',
        ),
      ],
      acknowledgeOutcomes: (keys) async => acked.addAll(keys),
    );

    expect(await importer.importOutcomes(), 1);
    expect(acked, ['a|1|dropped'], reason: 'b failed, so b and c stay stored');
  });

  test(
    'unknown outcome kinds are acknowledged without a history entry',
    () async {
      final recorder = _Recorder();
      final acked = <String>[];
      final importer = RelayOutcomeImporter(
        recorder: recorder,
        idGenerator: _Ids(),
        takeOutcomes: () async => const [
          RelayOutcomeRecord(
            clientAlertId: 'a',
            fallTimestamp: 1,
            outcome: 'future_kind',
            key: 'native-key',
          ),
        ],
        acknowledgeOutcomes: (keys) async => acked.addAll(keys),
      );

      expect(await importer.importOutcomes(), 0);
      expect(recorder.events, isEmpty);
      expect(acked, ['native-key']);
    },
  );

  test('a failing acknowledgement does not throw', () async {
    final importer = RelayOutcomeImporter(
      recorder: _Recorder(),
      idGenerator: _Ids(),
      takeOutcomes: () async => const [
        RelayOutcomeRecord(
          clientAlertId: 'a',
          fallTimestamp: 1,
          outcome: 'dropped',
        ),
      ],
      acknowledgeOutcomes: (keys) async => throw Exception('native gone'),
    );

    expect(await importer.importOutcomes(), 1);
  });

  test('new outcome kinds map to explicit history statuses', () {
    expect(
      RelayOutcomeImporter.statusFor('repair_not_delivered'),
      FallEventStatus.alertFailed,
    );
    expect(
      RelayOutcomeImporter.statusFor('cancel_unconfirmed'),
      FallEventStatus.cancellationPending,
    );
    expect(
      RelayOutcomeImporter.statusFor('cancelled_unsent'),
      FallEventStatus.cancelled,
    );
  });
  test('native success outcomes upgrade provisional history entries', () async {
    final recorder = _Recorder();
    final existing = <int, FallEventStatus>{
      1: FallEventStatus.alertFailed,
      2: FallEventStatus.cancellationPending,
      3: FallEventStatus.cancelled,
    };
    final importer = RelayOutcomeImporter(
      recorder: recorder,
      idGenerator: _Ids(),
      acknowledgeOutcomes: (_) async {},
      existingStatus: (ts) async => existing[ts.millisecondsSinceEpoch],
      takeOutcomes: () async => const [
        // Flutter recorded "failed", native relay later delivered it.
        RelayOutcomeRecord(
          clientAlertId: 'a',
          fallTimestamp: 1,
          outcome: 'created',
        ),
        // Flutter's cancel was unconfirmed, native relay confirmed it.
        RelayOutcomeRecord(
          clientAlertId: 'b',
          fallTimestamp: 2,
          outcome: 'cancelled',
        ),
        // A late "created" must not hide a confirmed cancellation.
        RelayOutcomeRecord(
          clientAlertId: 'c',
          fallTimestamp: 3,
          outcome: 'created',
        ),
      ],
    );

    expect(await importer.importOutcomes(), 2);
    expect(
      recorder.events.map(
        (e) => (e.timestamp.millisecondsSinceEpoch, e.status),
      ),
      [(1, FallEventStatus.alertSent), (2, FallEventStatus.cancelled)],
    );
  });

  test('replacement rules never downgrade a definitive outcome', () {
    bool r(FallEventStatus incoming, FallEventStatus? existing) =>
        RelayOutcomeImporter.shouldReplace(incoming, existing);

    expect(r(FallEventStatus.alertSent, null), isTrue);
    expect(r(FallEventStatus.alertSent, FallEventStatus.alertFailed), isTrue);
    expect(
      r(FallEventStatus.alertSent, FallEventStatus.cancellationPending),
      isTrue,
    );
    expect(r(FallEventStatus.alertSent, FallEventStatus.cancelled), isFalse);
    expect(r(FallEventStatus.cancelled, FallEventStatus.alertSent), isTrue);
    expect(r(FallEventStatus.alertFailed, FallEventStatus.alertSent), isFalse);
    expect(r(FallEventStatus.alertFailed, FallEventStatus.cancelled), isFalse);
    expect(
      r(FallEventStatus.alertFailed, FallEventStatus.timedOutNoSms),
      isTrue,
    );
    expect(
      r(FallEventStatus.cancellationPending, FallEventStatus.alertSent),
      isTrue,
    );
    expect(
      r(FallEventStatus.cancellationPending, FallEventStatus.cancelled),
      isFalse,
    );
    expect(
      RelayOutcomeImporter.statusFor('created'),
      FallEventStatus.alertSent,
    );
    expect(
      RelayOutcomeImporter.statusFor('cancelled'),
      FallEventStatus.cancelled,
    );
  });
}

class _FailingRecorder implements FallEventRecorder {
  _FailingRecorder({required this.failOnCall});

  final int failOnCall;
  var _calls = 0;

  @override
  Future<void> add(FallEvent event) async {
    _calls++;
    if (_calls == failOnCall) throw Exception('storage full');
  }
}
