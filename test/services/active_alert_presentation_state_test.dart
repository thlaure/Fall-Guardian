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
}
