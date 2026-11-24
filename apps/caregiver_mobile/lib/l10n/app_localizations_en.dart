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
  String get imHandlingIt => "I'm handling it";
  @override
  String fallDetectedFor(String name) => '$name may have fallen';
  @override
  String get yourContact => 'Your contact';
  @override
  String detectedOn(String date, String time) => 'Detected on $date at $time';
  @override
  String get justNow => 'just now';
  @override
  String minutesAgo(int minutes) => '$minutes min ago';
  @override
  String hoursAgo(int hours) => '$hours h ago';
  @override
  String daysAgo(int days) => days == 1 ? '1 day ago' : '$days days ago';
  @override
  String get openInMaps => 'Open in Maps';
  @override
  String get mapsUnavailable => 'No maps app could open this location.';
  @override
  String callEmergencyServices(String number) =>
      'Call emergency services ($number)';
  @override
  String get dialerUnavailable => 'Could not open the phone dialer.';
  @override
  String get alertDetailsTitle => 'Technical details';
  @override
  String coordinatesLabel(String latitude, String longitude) =>
      'Coordinates: $latitude, $longitude';
  @override
  String get reminderBanner => 'Reminder — no one has responded yet';
  @override
  String get handlingByMe => 'You are handling this';
  @override
  String get handlingByOther => 'Another caregiver is handling this';
  @override
  String handlingByOtherSince(String time) =>
      'Another caregiver is handling this since $time';
  @override
  String get closeAlert => 'Close';
  @override
  String moreAlertsWaiting(int count) =>
      count == 1 ? '1 more alert waiting' : '$count more alerts waiting';
  @override
  String fallAlertSemantics(String name) => 'Fall alert for $name';
  @override
  String get activeAlertGuidanceWithLocation =>
      'Tap “I\'m handling it” once you are taking care of this alert. If you cannot reach your contact, open the location in Maps and call emergency services.';
  @override
  String get activeAlertGuidanceWithoutLocation =>
      'Tap “I\'m handling it” once you are taking care of this alert. If you cannot reach your contact, call emergency services and explain that no location was provided.';
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
  String get protectedPersonNameFieldLabel => 'Protected person name';
  @override
  String get protectedPersonNameValidation =>
      'Enter a name with at least 2 characters';
  @override
  String get caregiverNameFieldLabel => 'Your caregiver name';
  @override
  String get caregiverNameValidation =>
      'Enter your name with at least 2 characters';
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
  @override
  String get removeProtectedPersonTooltip => 'Remove link';
  @override
  String removeProtectedPersonTitle(String name) => 'Remove $name?';
  @override
  String removeProtectedPersonBody(String name) =>
      'You will stop receiving fall alerts from $name. This does not delete their account or affect their other caregivers.';
  @override
  String get removeProtectedPersonCancel => 'Cancel';
  @override
  String get removeProtectedPersonConfirm => 'Remove';
  @override
  String removeProtectedPersonSuccess(String name) =>
      'The link with $name was removed.';
  @override
  String get removeProtectedPersonFailed =>
      'Failed to remove the link. Please try again.';

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
  String get statusAcknowledged => 'Handled by you';
  @override
  String get statusUnacknowledged => 'Waiting for you to respond';
  @override
  String get unknownDate => 'Unknown date';
}
