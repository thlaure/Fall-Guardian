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
}
