import 'dart:developer' as developer;

import 'package:geolocator/geolocator.dart';

import 'alert_ports.dart';

class LocationService implements AlertLocationProvider {
  /// Returns the current position, or null if unavailable.
  @override
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (error, stackTrace) {
      developer.log(
        'getCurrentPosition failed',
        name: 'LocationService',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String googleMapsUrl(double lat, double lng) =>
      'https://maps.google.com/?q=$lat,$lng';
}
