import 'dart:io';
import 'dart:ui';

import 'package:url_launcher/url_launcher.dart';

/// Map app URIs for a fall location.
///
/// Android: `geo:` opens the user's default maps app with a pin (Google Maps,
/// Waze, OsmAnd...). iOS: `maps.apple.com` is handled by Apple Maps and asks
/// for directions to the location. A web URL is the fallback when no app
/// accepts the native URI.
List<Uri> mapUrisFor({
  required double latitude,
  required double longitude,
  required bool isIOS,
}) {
  final coordinates = '$latitude,$longitude';
  final web = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': coordinates,
  });
  if (isIOS) {
    return [
      Uri.https('maps.apple.com', '/', {'daddr': coordinates}),
      web,
    ];
  }
  return [Uri.parse('geo:$coordinates?q=$coordinates'), web];
}

/// Local emergency number for the phone's region.
///
/// 911 is used in North America; 112 is the EU-wide number and is also
/// routed to local emergency services by GSM phones in most other countries.
/// The UI always shows the number on the button so the caregiver knows what
/// will be dialed.
String emergencyNumberFor(Locale deviceLocale) {
  return switch (deviceLocale.countryCode?.toUpperCase()) {
    'US' || 'CA' => '911',
    _ => '112',
  };
}

/// Opens external apps from the emergency screen.
abstract class AlertActions {
  /// Returns false when no installed app could open the location.
  Future<bool> openMap({required double latitude, required double longitude});

  /// Returns false when the phone dialer could not be opened.
  Future<bool> call(String phoneNumber);
}

// Plugin wrapper: URI choice is tested through mapUrisFor.
// coverage:ignore-start
class UrlLauncherAlertActions implements AlertActions {
  const UrlLauncherAlertActions();

  @override
  Future<bool> openMap({
    required double latitude,
    required double longitude,
  }) async {
    for (final uri in mapUrisFor(
      latitude: latitude,
      longitude: longitude,
      isIOS: Platform.isIOS,
    )) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Try the next URI (no app registered for this scheme).
      }
    }
    return false;
  }

  @override
  Future<bool> call(String phoneNumber) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: phoneNumber));
    } catch (_) {
      return false;
    }
  }
}

// coverage:ignore-end
