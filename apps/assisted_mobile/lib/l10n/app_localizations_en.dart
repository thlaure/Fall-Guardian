import 'app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  // ── Generic ──────────────────────────────────────────────────────────────
  @override
  String get appTitle => 'Fall Guardian';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get remove => 'Remove';
  @override
  String get required_ => 'Required';
  @override
  String get unitG => 'g';
  @override
  String get unitMs => 'ms';
  @override
  String get unitDeg => '°';

  // ── Home ─────────────────────────────────────────────────────────────────
  @override
  String get homeStatusTitle => 'Protected';
  @override
  String get homeStatusBody =>
      'Fall detection is active.\nA 30-second alert will appear if a fall is detected.';
  @override
  String get homeStatusUnlinkedTitle => 'No caregiver linked';
  @override
  String get homeStatusUnlinkedBody =>
      'Fall detection can run, but no caregiver will be alerted yet.\nAdd a caregiver before relying on monitoring.';
  @override
  String get homeContactsTitle => 'Caregivers';
  @override
  String homeCaregiverCount(int count) =>
      count == 1 ? '1 caregiver' : '$count caregivers';
  @override
  String get homeHistoryTitle => 'Fall History';
  @override
  String get homeFootnote =>
      'Monitoring active on your watch.\nKeep the watch app running in the background.';

  // ── Contacts ─────────────────────────────────────────────────────────────
  @override
  String get contactsScreenTitle => 'Caregivers';
  @override
  String contactsRemoveTitle(String name) => 'Remove $name from caregivers?';
  @override
  String get contactsEmpty => 'No contacts yet';
  @override
  String get contactsEmptyHint => 'Add caregivers to notify on fall detection.';
  @override
  String get addContact => 'Add Contact';
  @override
  String get editContact => 'Edit Contact';
  @override
  String get contactNameLabel => 'Name';
  @override
  String get contactPhoneLabel => 'Phone Number';
  @override
  String get contactsSyncFailedBanner => 'Backend sync failed';
  @override
  String get contactsSyncFailedHint =>
      'This contact is saved on this device only. Check that the backend is running and reachable.';
  @override
  String get contactsSavedLocallyOnly =>
      'Saved on this device only. Backend sync failed.';

  // ── Fall Alert ────────────────────────────────────────────────────────────
  @override
  String get fallAlertTitle => 'Fall Detected!';
  @override
  String get fallAlertBody =>
      'Cancel if you are OK. The event will still be saved in history.';
  @override
  String get gettingLocation => 'Getting your location…';
  @override
  String get sendingAlert => 'Sending alert…';
  @override
  String get alertSubmissionFailed =>
      'Alert submission failed. Contact your caregivers manually now.';
  @override
  String get alertSubmitted =>
      'Alert sent. Linked caregivers can see and acknowledge it.';
  @override
  String get confirmingCancellation => 'Confirming cancellation…';
  @override
  String get cancellationUnconfirmed =>
      'Cancellation was not confirmed. Caregivers may still be alerted.';
  @override
  String get cancelAlert => "I'm OK — Cancel Alert";

  // ── History ──────────────────────────────────────────────────────────────
  @override
  String get historyTitle => 'Fall History';
  @override
  String get clearHistoryTitle => 'Clear history?';
  @override
  String get clearHistoryBody =>
      'This will permanently delete all fall event records.';
  @override
  String get clear => 'Clear';
  @override
  String get historyEmpty => 'No fall events recorded';
  @override
  String get historyLoadFailed => 'Failed to load fall history.';
  @override
  String get statusAlertSent => 'Alert sent to caregivers';
  @override
  String get statusAlertFailed => 'Alert Failed';
  @override
  String get statusCancelled => 'Cancelled by protected person';
  @override
  String get statusCancellationPending => 'Cancellation confirmation pending';
  @override
  String get statusTimedOut => 'Timed Out';
  @override
  String notifiedLabel(String names) => 'Alert recipients: $names';
  @override
  String locationLabel(String coords) => 'Location: $coords';

  // ── Settings ─────────────────────────────────────────────────────────────
  @override
  String get settingsTitle => 'Settings';
  @override
  String get settingsSaved => 'Settings saved';
  @override
  String get watchConnectionSection => 'Watch connection';
  @override
  String get watchNotConnected => 'Watch not connected';
  @override
  String get watchConnectionStarting => 'Starting secure connection…';
  @override
  String get watchConnectionWaiting => 'Waiting for the watch to finish setup';
  @override
  String get watchConnectionFailed =>
      'Could not send setup to the watch. Check that it is nearby.';
  @override
  String get watchConnectionAppMissing =>
      'Install Fall Guardian on your watch, then try again.';
  @override
  String get watchConnectionNotPaired =>
      'No watch is paired with this phone yet.';
  @override
  String get watchConnectionNotReady =>
      'The watch connection is still starting. Try again in a moment.';
  @override
  String get watchConnectionExpired => 'Watch setup expired. Try again.';
  @override
  String get connectWatch => 'Connect watch';
  @override
  String get retryWatchConnection => 'Try again';
  @override
  String watchConnectionExpires(DateTime expiresAt) => 'Setup expires at '
      '${expiresAt.hour.toString().padLeft(2, '0')}:'
      '${expiresAt.minute.toString().padLeft(2, '0')}';
  @override
  String get thresholdsSection => 'Fall Detection Thresholds';
  @override
  String get thresholdsInfo =>
      'These thresholds control sensitivity. Lower free-fall and higher impact '
      'thresholds reduce false positives. Some falls lack a free-fall '
      'phase — impact + tilt alone will trigger an alert.';
  @override
  String get freeFallLabel => 'Free-fall threshold';
  @override
  String get freeFallDesc =>
      '‖accel‖ must drop below this to detect free-fall phase';
  @override
  String get impactLabel => 'Impact threshold';
  @override
  String get impactDesc => '‖accel‖ spike must exceed this to detect impact';
  @override
  String get tiltLabel => 'Tilt threshold';
  @override
  String get tiltDesc => 'Angle from upright must exceed this after impact';
  @override
  String get freeFallDurationLabel => 'Min free-fall duration';
  @override
  String get freeFallDurationDesc => 'Minimum duration of free-fall phase';
  @override
  String get resetDefaults => 'Reset to defaults';

  // ── Notifications ─────────────────────────────────────────────────────────
  @override
  String get notifTitle => '⚠️ Fall Detected';
  @override
  String get notifBody => 'Open app to cancel or send alert in 30 seconds';
}
