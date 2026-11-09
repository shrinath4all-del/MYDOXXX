import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import '../config/test_lab_config.dart';
import '../utils/error_messages.dart';
import '../utils/ist_clock.dart';

/// Synthetic location keeps concurrent demo roles nearby without collecting GPS.
class LabLocation {
  static Position get sample => Position(
        latitude: 18.5994,
        longitude: 73.7620,
        timestamp: IstClock.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
  static Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) =>
      TestLabConfig.enabled
          ? Future.value(sample)
          : Geolocator.getCurrentPosition(locationSettings: locationSettings);
  static Future<Position?> getLastKnownPosition() => TestLabConfig.enabled
      ? Future.value(sample)
      : Geolocator.getLastKnownPosition();
  static Future<LocationPermission> checkPermission() => TestLabConfig.enabled
      ? Future.value(LocationPermission.whileInUse)
      : Geolocator.checkPermission();
  static Future<LocationPermission> requestPermission() => TestLabConfig.enabled
      ? Future.value(LocationPermission.whileInUse)
      : Geolocator.requestPermission();
  static Future<bool> isLocationServiceEnabled() => TestLabConfig.enabled
      ? Future.value(true)
      : Geolocator.isLocationServiceEnabled();
}

Future<bool> labCanLaunchUrl(Uri uri) =>
    TestLabConfig.enabled ? Future.value(true) : launcher.canLaunchUrl(uri);

Future<bool> labLaunchUrl(Uri uri,
    {launcher.LaunchMode mode = launcher.LaunchMode.platformDefault}) async {
  if (TestLabConfig.enabled) {
    ErrorMessages.showGlobal(StateError(
        'Test lab: external phone calls, maps and document links are disabled.'));
    return false;
  }
  return launcher.launchUrl(uri, mode: mode);
}
