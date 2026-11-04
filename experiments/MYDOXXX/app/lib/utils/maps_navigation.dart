import '../services/app_database.dart';
import '../services/lab_device.dart';
import './safe_cast.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the hospital / clinic in Google Maps using the coordinates saved for
/// that hospital in the database (so navigation goes to the exact spot, not a
/// name search).
class MapsNavigation {
  MapsNavigation._();

  /// Saved coordinates of the hospital called [name] (from the `hospitals`
  /// collection), or null if it isn't registered / has no location.
  static Future<({double lat, double lng})?> hospitalCoordinates(
      String name) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    try {
      final snap = await AppDatabase.instance.collection('hospitals').get();
      for (final h in snap.docs) {
        final d = h.data();
        final hName =
            (d['name'] ?? d['hospital'] ?? '').toString().trim().toLowerCase();
        if (hName != wanted) continue;
        final lat = toNum(d['latitude'])?.toDouble();
        final lng = toNum(d['longitude'])?.toDouble();
        if (lat != null && lng != null) return (lat: lat, lng: lng);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _launch(String label, double? lat, double? lng) async {
    final query = (lat != null && lng != null)
        ? '$lat,$lng'
        : Uri.encodeComponent(label.isNotEmpty ? label : 'Hospital');
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await labCanLaunchUrl(url)) {
        await labLaunchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  /// Navigate to [name]. Uses [lat]/[lng] when given, otherwise the saved
  /// hospital coordinates; falls back to a name search only if the hospital
  /// has no saved location.
  static Future<void> toHospital(
    String name, {
    double? lat,
    double? lng,
  }) async {
    if (lat == null || lng == null) {
      final saved = await hospitalCoordinates(name);
      lat = saved?.lat;
      lng = saved?.lng;
    }
    await _launch(name, lat, lng);
  }

  /// Same, with a hint if the hospital has no saved location yet.
  static Future<void> toHospitalWithHint(
    BuildContext context,
    String name, {
    double? lat,
    double? lng,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (lat == null || lng == null) {
      final saved = await hospitalCoordinates(name);
      lat = saved?.lat;
      lng = saved?.lng;
      if (saved == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'This hospital has no saved location yet, so Maps will search by name.'),
        ));
      }
    }
    await _launch(name, lat, lng);
  }
}
