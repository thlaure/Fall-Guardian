import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native iOS alert copy describes linked-caregiver delivery', () {
    const managerPath = 'ios/Runner/WatchSessionManager.swift';
    const plistPath = 'ios/Runner/Info.plist';
    final manager = File(managerPath).readAsStringSync();
    final plist = File(plistPath).readAsStringSync();

    const expectedNotification =
        'content.body = "Open app to cancel — linked caregivers will be '
        'alerted in 30 seconds"';
    expect(
      manager,
      contains(expectedNotification),
      reason:
          'The native iOS notification must describe linked-caregiver alerts.',
    );

    expect(
      plist.toLowerCase(),
      isNot(contains('sms')),
      reason: 'iOS permission copy must not promise SMS delivery.',
    );
  });
}
