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
      'You will receive push alerts if a fall is detected on the protected person\'s device.';
  @override
  String get statusUnlinkedBody =>
      'Link with a protected person to start receiving fall alerts.';
  @override
  String get linkedSnackbar =>
      'Linked successfully! You will now receive fall alerts.';
  @override
  String get linkButton => 'Link with Protected Person';
  @override
  String get statusCardTitle => 'Status';
  @override
  String get howItWorksTitle => 'How it works';
  @override
  String get statusCardBody =>
      'Push notifications are active. Keep this app installed.';
  @override
  String get howItWorksBody =>
      '1. Ask the protected person to generate a code in their Fall Guardian app.\n'
      '2. Tap "Link" above and enter the code.\n'
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

  // ── Link ──────────────────────────────────────────────────────────────────
  @override
  String get linkScreenTitle => 'Link with Protected Person';
  @override
  String get enterInviteCodeTitle => 'Enter Invite Code';
  @override
  String get inviteCodeInstructions =>
      'Ask the protected person to generate a code in their Fall Guardian app.';
  @override
  String get codeFieldLabel => '8-character code';
  @override
  String get codeFieldValidation => 'Enter the full 8-character code';
  @override
  String get codeNotFound => 'Code not found or expired. Ask for a new code.';
  @override
  String inviteFailed(int code) => 'Failed to accept invite ($code).';
  @override
  String get connectionError => 'Connection error. Check the backend.';
  @override
  String get linkAsCaregiverButton => 'Link as Caregiver';
}
