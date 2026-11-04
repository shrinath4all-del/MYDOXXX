import '../config/test_lab_config.dart';
import 'lab_device.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  /// Map centre when the phone's position is unknown (central Pune).
  static const double defaultLat = 18.5204;
  static const double defaultLng = 73.8567;

  /// Returned when GPS is on but no position or place name was found.
  static const String notFound = 'Location Not Found';

  /// The result is one of the messages above, not a place name.
  static bool isError(String area) =>
      area.trim().isEmpty || area.toLowerCase().startsWith('location ');

  /// Fetch current live location and reverse-geocode to area/city name
  static Future<String> getCurrentLocation() async {
    if (TestLabConfig.enabled) return 'Wakad';
    try {
      bool serviceEnabled = await LabLocation.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Location Disabled in Settings';
      }

      LocationPermission permission = await LabLocation.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await LabLocation.requestPermission();
        if (permission == LocationPermission.denied) {
          return 'Location Permission Denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return 'Location Permission Denied';
      }

      // Get current GPS position
      Position? position;
      try {
        position = await LabLocation.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        // an old cached fix can be in another city: only use a recent one
        final last = await LabLocation.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp).inMinutes < 5) {
          position = last;
        }
      }

      if (position == null) {
        return notFound;
      }

      // 1. Try Native Geocoding if on Android / iOS
      if (!kIsWeb) {
        try {
          final List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );

          if (placemarks.isNotEmpty) {
            final Placemark place = placemarks.first;
            final String subLocality = place.subLocality ?? place.thoroughfare ?? '';
            final String locality = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? '';
            final String country = place.country ?? '';

            if (subLocality.isNotEmpty && locality.isNotEmpty) {
              return '$subLocality, $locality';
            } else if (locality.isNotEmpty && country.isNotEmpty) {
              return '$locality, $country';
            } else if (locality.isNotEmpty) {
              return locality;
            }
          }
        } catch (_) {
          // Native geocoding unavailable, fallback to Web API reverse geocode
        }
      }

      // 2. HTTP Reverse Geocoding via OpenStreetMap Nominatim API (Works on Web & Mobile)
      final areaName = await _reverseGeocodeApi(position.latitude, position.longitude);
      if (areaName != null && areaName.isNotEmpty) {
        return areaName;
      }

      return notFound;
    } catch (e) {
      return notFound;
    }
  }

  /// Free Reverse Geocoding API via Nominatim OpenStreetMap
  static Future<String?> _reverseGeocodeApi(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1');
      final response = await http.get(
        url,
        headers: {'User-Agent': 'MyDoxApp/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          final String area = address['suburb'] ??
              address['neighbourhood'] ??
              address['residential'] ??
              address['road'] ??
              '';

          final String city = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['county'] ??
              address['state'] ??
              '';

          final String country = address['country'] ?? '';

          if (area.isNotEmpty && city.isNotEmpty) {
            return '$area, $city';
          } else if (city.isNotEmpty && country.isNotEmpty) {
            return '$city, $country';
          } else if (city.isNotEmpty) {
            return city;
          } else if (area.isNotEmpty) {
            return area;
          }
        }
      }
    } catch (_) {
      // Network lookup failed
    }
    return null;
  }
}
