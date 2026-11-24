import 'package:caregiver_app/services/active_alert_presentation_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('show presents a new alert once', () {
    final state = ActiveAlertPresentationState();

    final firstPresentation = state.show({
      'alertId': 'alert-1',
      'fallTimestamp': '2026-06-16T08:00:00+00:00',
    });
    final duplicatePresentation = state.show({
      'alertId': 'alert-1',
      'fallTimestamp': '2026-06-16T08:00:00+00:00',
    });

    expect(firstPresentation, isTrue);
    expect(duplicatePresentation, isFalse);
    expect(state.activeAlert?['alertId'], 'alert-1');
  });

  test('show ignores invalid alert payloads', () {
    final state = ActiveAlertPresentationState();

    expect(state.show({'fallTimestamp': '2026-06-16T08:00:00+00:00'}), isFalse);
    expect(state.show({'alertId': ''}), isFalse);
    expect(state.activeAlert, isNull);
  });

  test('dismissActive prevents the same alert from being reopened', () {
    final state = ActiveAlertPresentationState();

    expect(state.show({'alertId': 'alert-1'}), isTrue);
    state.dismissActive();

    expect(state.activeAlert, isNull);
    expect(state.show({'alertId': 'alert-1'}), isFalse);
    expect(state.show({'alertId': 'alert-2'}), isTrue);
    expect(state.activeAlert?['alertId'], 'alert-2');
  });

  test('clearActive removes current alert without dismissing it', () {
    final state = ActiveAlertPresentationState();

    expect(state.show({'alertId': 'alert-1'}), isTrue);
    expect(state.clearActive(), isTrue);

    expect(state.activeAlert, isNull);
    expect(state.show({'alertId': 'alert-1'}), isTrue);
  });

  test('clearActive returns false when no alert is active', () {
    final state = ActiveAlertPresentationState();

    expect(state.clearActive(), isFalse);
  });

  test('dismissActive prunes the oldest dismissed alert past the cap', () {
    final state = ActiveAlertPresentationState();

    for (var i = 0; i < 33; i++) {
      expect(state.show({'alertId': 'alert-$i'}), isTrue);
      state.dismissActive();
    }

    // The 33rd dismissal evicts the oldest id (alert-0), so it can be
    // re-shown even though it was previously dismissed.
    expect(state.show({'alertId': 'alert-0'}), isTrue);
  });

  test('queues alerts for several people and presents them in order', () {
    final state = ActiveAlertPresentationState();

    expect(state.show({'alertId': 'alert-1'}), isTrue);
    expect(state.show({'alertId': 'alert-2'}), isTrue);

    expect(state.activeAlert?['alertId'], 'alert-1');
    expect(state.waitingCount, 1);

    state.dismissActive();

    expect(state.activeAlert?['alertId'], 'alert-2');
    expect(state.waitingCount, 0);
  });

  test('newer data for a queued alert updates its live listenable', () {
    final state = ActiveAlertPresentationState();
    state.show({'alertId': 'alert-1', 'latitude': '48.1'});
    final live = state.activeAlertListenable!;
    var notifications = 0;
    live.addListener(() => notifications++);

    expect(
      state.show({'alertId': 'alert-1', 'acknowledgementCount': '1'}),
      isFalse,
    );

    expect(notifications, 1);
    expect(live.value['latitude'], '48.1');
    expect(live.value['acknowledgementCount'], '1');
  });

  test('a reminder reopens an alert closed without handling it', () {
    final state = ActiveAlertPresentationState();
    state.show({'alertId': 'alert-1'});
    state.dismissActive();

    expect(state.show({'alertId': 'alert-1', 'reminder': '0'}), isFalse);
    expect(state.show({'alertId': 'alert-1', 'reminder': '1'}), isTrue);
    expect(state.activeAlert?['reminder'], '1');
  });

  test('empty state exposes no active alert', () {
    final state = ActiveAlertPresentationState();

    state.dismissActive();

    expect(state.activeAlertListenable, isNull);
    expect(state.waitingCount, 0);
  });

  test('waiting count is published live for the open screen', () {
    final state = ActiveAlertPresentationState();
    final counts = <int>[];
    state.waitingCountListenable.addListener(
      () => counts.add(state.waitingCountListenable.value),
    );

    state.show({'alertId': 'alert-1'});
    state.show({'alertId': 'alert-2'});
    state.show({'alertId': 'alert-3'});
    state.dismissActive();
    state.clearActive();

    expect(counts, [1, 2, 1, 0]);
  });

  test('update only merges into queued alerts', () {
    final state = ActiveAlertPresentationState();
    state.show({'alertId': 'alert-1'});
    final live = state.activeAlertListenable!;

    expect(
      state.update({'alertId': 'unknown', 'status': 'acknowledged'}),
      isFalse,
    );
    expect(
      state.update({'alertId': 'alert-1', 'status': 'acknowledged'}),
      isTrue,
    );

    expect(live.value['status'], 'acknowledged');
    expect(state.waitingCount, 0);
    expect(state.update({'status': 'acknowledged'}), isFalse);
  });

  test('retainOnly drops alerts the backend no longer reports', () {
    final state = ActiveAlertPresentationState();
    state.show({'alertId': 'alert-1'});
    state.show({'alertId': 'alert-2'});
    state.show({'alertId': 'alert-3'});

    expect(state.retainOnly({'alert-1', 'alert-3'}), isTrue);
    expect(state.waitingCountListenable.value, 1);
    expect(state.retainOnly({'alert-1', 'alert-3'}), isFalse);

    state.dismissActive();
    expect(state.activeAlert?['alertId'], 'alert-3');
  });
}
