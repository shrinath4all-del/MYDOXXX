import '../config/test_lab_config.dart';
import 'app_database.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/stream_cache.dart';

/// App pictures come from Firestore `images_master`; each document holds only
/// where the picture is:
///
///   key:    'specialty:Cardiologist' / 'service:nurse' / 'lab_test:ECG' …
///           (the document id may be the key too)
///   path:   a Firebase Storage path ('images_master/cardiologist.png'),
///           a web link ('https://…') or a bundled picture ('assets/…')
///   active: optional, false hides it
///
/// Screens ask for a key and give the bundled picture to use until the
/// admin adds one (see MasterImage).
class ImagesMaster {
  ImagesMaster._();

  static const String collection = 'images_master';

  static String specialty(String name) => 'specialty:$name';
  static String service(String name) => 'service:$name';
  static String labTest(String name) => 'lab_test:$name';
  static String therapy(String name) => 'therapy:$name';
  static String careService(String name) => 'care_service:$name';
  static String banner(String name) => 'banner:$name';

  /// Keys compare without case or extra spaces.
  static String normalize(String key) =>
      key.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static final StreamCache _streams = StreamCache();

  /// key -> path for every active picture (one shared connection).
  static Stream<Map<String, String>> paths() =>
      _streams.get('all', () {
        if (TestLabConfig.enabled) return Stream.value(const <String, String>{});
        try {
          return AppDatabase.instance
              .collection(collection)
              .snapshots()
              .map((s) => latest = pathsOf(s));
        } catch (_) {
          return Stream.value(const <String, String>{}); // no Firebase (tests)
        }
      });

  /// The last list read, so a picture built later shows straight away
  /// instead of waiting a frame for the stream.
  static Map<String, String>? latest;

  static StreamSubscription<Map<String, String>>? _warm;

  /// Called once at start-up: reads the list while the splash and login show
  /// (and keeps it open), and downloads the pictures of the patient home and
  /// doctor list into the phone's image cache, so they show at once.
  static void warmUp() {
    if (TestLabConfig.enabled || _warm != null || kIsWeb) return;
    var fetched = false;
    _warm = paths().listen((all) async {
      if (fetched || all.isEmpty) return;
      fetched = true;
      for (final e in all.entries) {
        if (!e.key.startsWith('service:') &&
            !e.key.startsWith('banner:') &&
            !e.key.startsWith('specialty:')) {
          continue;
        }
        final url = isWeb(e.value)
            ? e.value
            : isAsset(e.value)
                ? null
                : await downloadUrl(e.value);
        if (url == null) continue;
        try {
          await DefaultCacheManager().getSingleFile(url);
        } catch (_) {} // shown (and fetched again) by the screen later
      }
    }, onError: (_) {});
  }

  static Map<String, String> pathsOf(QuerySnapshot<Map<String, dynamic>> s) {
    final out = <String, String>{};
    for (final d in s.docs) {
      final data = d.data();
      if (data['active'] == false) continue;
      final path = (data['path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      final key = (data['key'] ?? d.id).toString();
      out[normalize(key)] = path;
    }
    return out;
  }

  static final Map<String, Future<String?>> _urls = {};

  /// Web link for a Storage path (cached for the app's lifetime).
  static Future<String?> downloadUrl(String path) =>
      TestLabConfig.enabled ? Future.value(null) :
      _urls[path] ??= FirebaseStorage.instance
          .ref(path)
          .getDownloadURL()
          .then<String?>((u) => u)
          .catchError((_) => null);

  static bool isAsset(String path) => path.startsWith('assets/');
  static bool isWeb(String path) =>
      path.startsWith('http://') || path.startsWith('https://');
}
