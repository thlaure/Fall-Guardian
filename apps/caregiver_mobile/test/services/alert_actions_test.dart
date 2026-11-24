import 'dart:ui';

import 'package:caregiver_app/services/alert_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android opens the default maps app through geo: first', () {
    final uris = mapUrisFor(latitude: 48.8566, longitude: 2.3522, isIOS: false);

    expect(uris.first.toString(), 'geo:48.8566,2.3522?q=48.8566,2.3522');
    expect(uris.last.host, 'www.google.com');
    expect(uris.last.queryParameters['query'], '48.8566,2.3522');
  });

  test('iOS asks Apple Maps for directions first', () {
    final uris = mapUrisFor(latitude: 48.8566, longitude: 2.3522, isIOS: true);

    expect(uris.first.host, 'maps.apple.com');
    expect(uris.first.queryParameters['daddr'], '48.8566,2.3522');
    expect(uris.last.scheme, 'https');
  });

  test('emergency number follows the phone region', () {
    expect(emergencyNumberFor(const Locale('en', 'US')), '911');
    expect(emergencyNumberFor(const Locale('fr', 'CA')), '911');
    expect(emergencyNumberFor(const Locale('fr', 'FR')), '112');
    expect(emergencyNumberFor(const Locale('en', 'GB')), '112');
    expect(emergencyNumberFor(const Locale('en')), '112');
  });
}
