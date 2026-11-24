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

/// Phone region (ISO 3166 country code) from the device's preferred
/// locales, e.g. `FR` for `fr_FR` or `en_FR`. Flutter does not expose the
/// OS region setting separately, so the first locale carrying a country
/// code is used; null when none does.
String? deviceRegionFrom(List<Locale> deviceLocales) {
  for (final locale in deviceLocales) {
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) return country.toUpperCase();
  }
  return null;
}

/// Local emergency number for the phone's region.
///
/// 911 in the US and Canada; 112 everywhere else, including when the region
/// is unknown: 112 is the EU-wide number and GSM phones route it to local
/// emergency services in most other countries. The app language is never
/// used (an English UI does not mean the caregiver is in North America).
/// The UI always shows the number on the button.
String emergencyNumberFor(String? region) {
  return switch (region?.toUpperCase()) {
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
