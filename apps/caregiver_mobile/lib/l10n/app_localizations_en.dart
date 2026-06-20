import 'app_localizations.dart';

class AppLocalizationsEn extends AppLocalizations {
  // ── Generic ───────────────────────────────────────────────────────────────
  @override
  String get appTitle => 'Fall Guardian Caregiver';

  // ── Home ──────────────────────────────────────────────────────────────────
  @override
  String get statusLinkedTitle => 'Monitoring Active';
  @override
  String get statusUnlinkedTitle => 'Not Linked Yet';
  @override
  String get statusLinkedBody =>
      'You will receive push alerts if a fall is detected on a linked protected person\'s device.';
  @override
  String get statusUnlinkedBody =>
      'Link with a protected person to start receiving fall alerts.';
  @override
  String get linkedSnackbar =>
      'Linked successfully! You will now receive fall alerts.';
  @override
  String get linkButton => 'Add protected person';
  @override
  String get relinkButton => 'Add another protected person';
  @override
  String get protectedPersonsButton => 'View protected persons';
  @override
  String get statusCardTitle => 'Status';
  @override
  String get howItWorksTitle => 'How it works';
  @override
  String get statusCardBody =>
      'Push notifications are active. Keep this app installed.';
  @override
  String get howItWorksBody =>
      '1. Ask each protected person to generate a code in their Fall Guardian app.\n'
      '2. Tap "Add protected person" above and enter the code.\n'
      '3. You\'ll receive push alerts on every detected fall.';
  @override
  String get importantTitle => 'Important';
  @override
  String get importantBody =>
      'Keep notifications enabled for this app. Fall alerts are delivered as '
      'data-only messages — your phone must be on and connected.';
  @override
  String get homeFootnote =>
      'Separate apps keep the protected-person and caregiver flows cleaner, '
      'safer, and easier to maintain.';

  // ── Active Alert ──────────────────────────────────────────────────────────
  @override
  String get fallDetectedTitle => 'FALL DETECTED';
  @override
  String detectedAt(String time) => 'Detected at $time';
  @override
  String get locationTitle => 'Location';
  @override
  String get alertIdTitle => 'Alert ID';
  @override
  String get acknowledge => 'Acknowledge';
  @override
  String get activeAlertGuidanceWithLocation =>
      'Acknowledge when you have seen this alert. If you cannot reach the protected person, use the location below and call emergency services.';
  @override
  String get activeAlertGuidanceWithoutLocation =>
      'Acknowledge when you have seen this alert. If you cannot reach the protected person, call emergency services and explain that no location was provided.';
  @override
  String get activeAlertEmergencyTitle => 'Emergency actions';
  @override
  String get activeAlertEmergencyBody =>
      'Call the protected person first when possible. If there is no answer or the situation looks serious, call emergency services.';

  // ── Link ──────────────────────────────────────────────────────────────────
  @override
  String get linkScreenTitle => 'Add Protected Person';
  @override
  String get enterInviteCodeTitle => 'Enter Invite Code';
  @override
  String get inviteCodeInstructions =>
      'Ask the protected person to generate a code in their Fall Guardian app. You can repeat this for multiple people.';
  @override
  String get codeFieldLabel => '32-character invite code';
  @override
  String get codeFieldValidation => 'Enter the full 32-character code';
  @override
  String get codeNotFound => 'Code not found or expired. Ask for a new code.';
  @override
  String inviteFailed(int code) => 'Failed to accept invite ($code).';
  @override
  String get connectionError =>
      'Connection error. Check your network and that the backend is reachable.';
  @override
  String get linkAsCaregiverButton => 'Add as Caregiver';

  // ── Protected Persons ─────────────────────────────────────────────────────
  @override
  String get protectedPersonsTitle => 'Protected persons';
  @override
  String get protectedPersonsLoadFailed => 'Failed to load protected persons';
  @override
  String get protectedPersonsEmptyTitle => 'No protected persons yet';
  @override
  String get protectedPersonsEmptyBody =>
      'Ask a protected person to generate an invite code, then add them here.';
  @override
  String get protectedPersonDeviceIdTitle => 'Device ID';
  @override
  String protectedPersonsCount(int count) =>
      count == 1 ? '1 protected person' : '$count protected persons';

  // ── History ───────────────────────────────────────────────────────────────
  @override
  String get historyTitle => 'Fall History';
  @override
  String get historyLoadFailed => 'Failed to load history';
  @override
  String get retry => 'Retry';
  @override
  String get historyEmpty => 'No fall alerts yet';
  @override
  String protectedPersonLabel(int number) => 'Protected person $number';
  @override
  String protectedPersonSubtitle(String platform, String shortId) =>
      '${platform.toUpperCase()} device $shortId';
  @override
  String alertCountLabel(int count) => count == 1 ? '1 alert' : '$count alerts';
  @override
  String get statusStoppedByProtectedPerson => 'Cancelled by protected person';
  @override
  String get statusAcknowledged => 'Acknowledged by caregiver';
  @override
  String get statusUnacknowledged => 'Needs caregiver acknowledgement';
  @override
  String get unknownDate => 'Unknown date';
}
