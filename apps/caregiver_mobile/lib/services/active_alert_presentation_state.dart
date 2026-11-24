import 'package:flutter/foundation.dart';

/// Tracks which fall alerts must be shown on the emergency screen.
///
/// Alerts are queued (a caregiver may protect several people) and shown one
/// at a time, oldest first. Each queued alert has a [ValueListenable] so the
/// visible screen updates when a reminder push or a poll brings newer data
/// (e.g. another caregiver started handling it).
class ActiveAlertPresentationState {
  static const _maxDismissedAlerts = 32;

  final Set<String> _dismissedAlertIds = <String>{};
  final List<String> _queue = <String>[];
  final Map<String, ValueNotifier<Map<String, dynamic>>> _alerts = {};

  /// Alert currently at the front of the queue.
  Map<String, dynamic>? get activeAlert =>
      _queue.isEmpty ? null : _alerts[_queue.first]!.value;

  /// Live data for the alert at the front of the queue.
  ValueListenable<Map<String, dynamic>>? get activeAlertListenable =>
      _queue.isEmpty ? null : _alerts[_queue.first];

  /// Number of queued alerts behind the active one.
  int get waitingCount => _queue.isEmpty ? 0 : _queue.length - 1;

  /// Queues [data]. Returns true only for an alert not seen before, so the
  /// caller reports receipt once. Newer data for a queued alert is merged.
  bool show(Map<String, dynamic> data) {
    final incomingAlertId = alertId(data);
    if (incomingAlertId == null) return false;

    final existing = _alerts[incomingAlertId];
    if (existing != null) {
      existing.value = {...existing.value, ...data};
      return false;
    }

    // A reminder means nobody has responded yet: show it again even if this
    // caregiver closed the screen earlier without saying they handle it.
    if (data['reminder'] == '1') {
      _dismissedAlertIds.remove(incomingAlertId);
    }
    if (_dismissedAlertIds.contains(incomingAlertId)) {
      return false;
    }

    _queue.add(incomingAlertId);
    _alerts[incomingAlertId] = ValueNotifier(Map<String, dynamic>.of(data));
    return true;
  }

  /// Removes the active alert and prevents it from being reopened.
  void dismissActive() {
    if (_queue.isEmpty) return;
    final currentAlertId = _queue.removeAt(0);
    _alerts.remove(currentAlertId);
    _dismissedAlertIds.add(currentAlertId);
    _pruneDismissedAlerts();
  }

  /// Drops every queued alert without dismissing them (the backend reports
  /// that nothing is active anymore). Returns true if anything was removed.
  bool clearActive() {
    if (_queue.isEmpty) {
      return false;
    }

    _queue.clear();
    _alerts.clear();
    return true;
  }

  static String? alertId(Map<String, dynamic> data) {
    final alertId = data['alertId'];
    return alertId is String && alertId.isNotEmpty ? alertId : null;
  }

  void _pruneDismissedAlerts() {
    while (_dismissedAlertIds.length > _maxDismissedAlerts) {
      _dismissedAlertIds.remove(_dismissedAlertIds.first);
    }
  }
}
