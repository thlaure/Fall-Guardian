class ActiveAlertPresentationState {
  static const _maxDismissedAlerts = 32;

  final Set<String> _dismissedAlertIds = <String>{};

  Map<String, dynamic>? activeAlert;

  bool show(Map<String, dynamic> data) {
    final incomingAlertId = alertId(data);
    if (incomingAlertId == null ||
        _dismissedAlertIds.contains(incomingAlertId)) {
      return false;
    }

    final activeAlertId = activeAlert == null ? null : alertId(activeAlert!);
    if (activeAlertId == incomingAlertId) {
      return false;
    }

    activeAlert = data;
    return true;
  }

  void dismissActive() {
    final currentAlertId = activeAlert == null ? null : alertId(activeAlert!);
    if (currentAlertId != null) {
      _dismissedAlertIds.add(currentAlertId);
      _pruneDismissedAlerts();
    }
    activeAlert = null;
  }

  bool clearActive() {
    if (activeAlert == null) {
      return false;
    }

    activeAlert = null;
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
