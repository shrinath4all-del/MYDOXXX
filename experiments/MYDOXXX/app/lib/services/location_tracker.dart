import '../config/test_lab_config.dart';
import 'app_database.dart';
import 'lab_device.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/ist_clock.dart';

/// Keeps an on-duty provider's live position saved while the app is open
/// AND in the background (doctors while Online, ambulances while signed in).
///
///   Android: a location foreground service with a permanent notification
///            ("MyDox is sharing your location"), so the system keeps it
///            running in the background.
///   iOS:     background location updates (the blue location pill shows).
///
/// "While using the app" permission is enough: tracking is always started
/// from the open app. Saving is throttled (see [shouldSave]) to spare the
/// battery and Firestore writes. Web and desktop are not tracked in the
/// background (the screens keep their foreground refresh there).
class LocationTracker {
  LocationTracker._();

  static StreamSubscription<Position>? _sub;
  static String? _collection;
  static String? _uid;
  static Position? _lastSaved;
  static DateTime? _lastSavedAt;
  static void Function(Position)? _onPosition;

  /// The user refused location in this session: not asked again until the
  /// app restarts (screens call [start] on every profile update).
  static bool _refused = false;

  /// Save at most every [minInterval]; sooner once moved [minDistanceM].
  static const Duration minInterval = Duration(seconds: 30);
  static const Duration minIntervalWhenMoving = Duration(seconds: 10);
  static const double minDistanceM = 100;

  static bool get isRunning => _sub != null;

  /// Whether background tracking is supported on this device.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Starts tracking [collection]/[uid] (e.g. 'doctors'/uid). Returns false
  /// when location is off, permission is refused, or the platform has no
  /// background tracking (callers then keep their foreground refresh).
  static Future<bool> start({
    required String collection,
    required String uid,
    void Function(Position position)? onPosition,
  }) async {
    if (TestLabConfig.enabled || !supported) return false;
    _onPosition = onPosition;
    if (_sub != null && _collection == collection && _uid == uid) return true;
    await stop();
    try {
      if (!await LabLocation.isLocationServiceEnabled()) return false;
      var permission = await LabLocation.checkPermission();
      if (permission == LocationPermission.denied) {
        if (_refused) return false;
        permission = await LabLocation.requestPermission();
        if (permission == LocationPermission.denied) _refused = true;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return false;
      }
      _collection = collection;
      _uid = uid;
      _onPosition = onPosition;
      _sub = Geolocator.getPositionStream(locationSettings: _settings())
          .listen(_onUpdate, onError: (Object e) {
        debugPrint('Location tracking error: $e');
      });
      return true;
    } catch (e) {
      debugPrint('Location tracking could not start: $e');
      return false;
    }
  }

  /// Stops tracking and removes the Android notification.
  static Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    _collection = null;
    _uid = null;
    _lastSaved = null;
    _lastSavedAt = null;
    _onPosition = null;
    await sub?.cancel();
  }

  static LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MyDox is sharing your location',
          notificationText:
              'While you are on duty, so nearby patients and emergencies reach you.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 30,
      activityType: ActivityType.otherNavigation,
      allowBackgroundLocationUpdates: true,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }

  /// Whether a new position is worth saving: the first one, then every
  /// [minInterval], or every [minIntervalWhenMoving] once moved
  /// [minDistanceM] (fast-moving ambulances stay current).
  @visibleForTesting
  static bool shouldSave({
    required DateTime now,
    DateTime? lastSavedAt,
    double? movedMetres,
  }) {
    if (lastSavedAt == null) return true;
    final elapsed = now.difference(lastSavedAt);
    if (elapsed >= minInterval) return true;
    return (movedMetres ?? 0) >= minDistanceM &&
        elapsed >= minIntervalWhenMoving;
  }

  static Future<void> _onUpdate(Position p) async {
    _onPosition?.call(p);
    final collection = _collection, uid = _uid;
    if (collection == null || uid == null) return;
    final now = IstClock.now();
    final last = _lastSaved;
    final moved = last == null
        ? null
        : Geolocator.distanceBetween(
            last.latitude, last.longitude, p.latitude, p.longitude);
    if (!shouldSave(now: now, lastSavedAt: _lastSavedAt, movedMetres: moved)) {
      return;
    }
    _lastSaved = p;
    _lastSavedAt = now;
    try {
      await AppDatabase.instance.collection(collection).doc(uid).set({
        'latitude': p.latitude,
        'longitude': p.longitude,
        'locationUpdatedAt': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Could not save live location: $e');
    }
  }
}

/// Whether two profile snapshots differ only in the live position (written
/// by the background location tracker every ~30 s).
bool sameExceptLocation(Map<String, dynamic> a, Map<String, dynamic> b) {
  const skip = {'latitude', 'longitude', 'locationUpdatedAt'};
  final keys = {...a.keys, ...b.keys}.where((k) => !skip.contains(k));
  for (final k in keys) {
    if (!_deepEquals(a[k], b[k])) return false;
  }
  return true;
}

bool _deepEquals(dynamic x, dynamic y) {
  if (x is Map && y is Map) {
    if (x.length != y.length) return false;
    for (final k in x.keys) {
      if (!y.containsKey(k) || !_deepEquals(x[k], y[k])) return false;
    }
    return true;
  }
  if (x is List && y is List) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (!_deepEquals(x[i], y[i])) return false;
    }
    return true;
  }
  return x == y;
}
