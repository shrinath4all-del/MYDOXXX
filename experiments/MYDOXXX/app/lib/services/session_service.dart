import 'app_database.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ist_clock.dart';

/// Thrown at login when the account is already signed in on another device.
class SessionConflictException implements Exception {
  final String device;
  final DateTime? since;
  SessionConflictException(this.device, this.since);
  @override
  String toString() => 'This account is signed in on another device.';
}

/// One signed-in device per account.
///
/// Each login on a device claims the account: a fresh random session id is
/// saved on this device and on `users/{uid}.sessionId`. A device whose saved
/// id no longer matches the account's id has been replaced by a newer login,
/// and is signed out (see SessionGuard).
class SessionService {
  SessionService._();

  static const String _key = 'mydox_session_id';

  /// Each account keeps its own saved id. Browser tabs share one storage, so a
  /// single shared key would let a second account signed in on another tab
  /// overwrite it and sign the first one out.
  static String _keyFor(String? uid) {
    try {
      uid ??= FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // Firebase not started (tests): the shared key
    }
    return (uid == null || uid.isEmpty) ? _key : '${_key}_$uid';
  }

  /// True once the splash screen has opened the login / home screen.
  static bool appReady = false;

  // While a login is being completed the check is paused, so the device that
  // is logging in is not signed out by the old session id it still sees.
  static DateTime _pausedUntil = IstClock.fromEpochMs(0);
  static bool get paused => IstClock.now().isBefore(_pausedUntil);
  // Long enough for a slow network: OTP, profile load and the session write
  // can take minutes on weak 3G. Login always calls resume() when it ends.
  static void pause([Duration d = const Duration(minutes: 10)]) =>
      _pausedUntil = IstClock.now().add(d);

  /// Bumped every time the pause ends. Snapshots that arrived while paused
  /// were ignored, so the guard re-checks the account against the server then
  /// (two devices logging in at once: the one that lost finds out here).
  static final ValueNotifier<int> recheck = ValueNotifier<int>(0);

  static void resume() {
    _pausedUntil = IstClock.fromEpochMs(0);
    recheck.value++;
  }

  static String _newId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String get _device {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name; // android / iOS / windows ...
  }

  /// Kind of device this is, as recorded in the account's session.
  static String get deviceLabel => _device;

  static Future<String?> localId([String? uid]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final own = prefs.getString(_keyFor(uid));
      if (own != null && own.isNotEmpty) return own;
      // Saved before ids were kept per account: carry it over. It only counts
      // if it matches the account's session (compared by the caller), so an
      // id left by another account on this browser changes nothing.
      final legacy = prefs.getString(_key);
      if (legacy != null && legacy.isNotEmpty && _keyFor(uid) != _key) {
        await prefs.setString(_keyFor(uid), legacy);
        return legacy;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearLocal([String? uid]) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_keyFor(uid));
    } catch (_) {}
  }

  /// This device becomes the account's only active session. Any other device
  /// signed in to the same account is signed out the next time it syncs.
  static Future<void> claim(String uid) async {
    final id = _newId();
    // save locally first, so our own listener sees a matching id
    try {
      await (await SharedPreferences.getInstance()).setString(_keyFor(uid), id);
    } catch (_) {}
    await AppDatabase.instance.collection('users').doc(uid).set({
      'sessionId': id,
      'sessionDevice': _device,
      'sessionAt': IstClock.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Re-publish this device's existing id (account had none recorded).
  static Future<void> publish(String uid, String id) =>
      AppDatabase.instance.collection('users').doc(uid).set({
        'sessionId': id,
        'sessionDevice': _device,
        'sessionAt': IstClock.now().toIso8601String(),
      }, SetOptions(merge: true));

  /// The session currently recorded for the account (empty id: none).
  static Future<({String id, String device, DateTime? at})> remoteSession(
      String uid) async {
    try {
      final d = (await AppDatabase.instance
              .collection('users')
              .doc(uid)
              .get())
          .data();
      return (
        id: (d?['sessionId'] ?? '').toString(),
        device: (d?['sessionDevice'] ?? 'another device').toString(),
        at: IstClock.tryParse((d?['sessionAt'] ?? '').toString()),
      );
    } catch (_) {
      return (id: '', device: '', at: null);
    }
  }

  /// This device signed out on purpose: free the account (only if this
  /// device is the one that holds it) so the next login anywhere is clean.
  static Future<void> release(String uid) async {
    final local = await localId(uid);
    if (local == null || local.isEmpty) return;
    try {
      final ref = AppDatabase.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if ((snap.data()?['sessionId'] ?? '').toString() == local) {
        await ref.update({
          'sessionId': FieldValue.delete(),
          'sessionDevice': FieldValue.delete(),
          'sessionAt': FieldValue.delete(),
        });
      }
    } catch (_) {}
  }
}
