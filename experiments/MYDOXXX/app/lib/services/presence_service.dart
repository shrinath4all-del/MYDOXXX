import 'app_database.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// "Online" in chats: while the app is open and in front, the signed-in
/// account writes `users/{uid}.lastActiveAt` every minute. Someone counts as
/// online when that is less than [onlineWithin] old.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService _i = PresenceService._();

  static const Duration beat = Duration(minutes: 1);
  static const Duration onlineWithin = Duration(minutes: 2);

  String? _uid;
  Timer? _timer;

  /// Called after sign-in (see PushService.registerForUser).
  static void start(String uid) {
    if (_i._uid == uid) return;
    stop();
    _i._uid = uid;
    WidgetsBinding.instance.addObserver(_i);
    _i._resume();
  }

  /// Called on sign-out.
  static void stop() {
    _i._timer?.cancel();
    _i._timer = null;
    if (_i._uid != null) WidgetsBinding.instance.removeObserver(_i);
    _i._uid = null;
  }

  void _resume() {
    _timer?.cancel();
    _write();
    _timer = Timer.periodic(beat, (_) => _write());
  }

  void _write() {
    final uid = _uid;
    if (uid == null) return;
    AppDatabase.instance.collection('users').doc(uid).set(
        {'lastActiveAt': DateTime.now().toIso8601String()},
        SetOptions(merge: true)).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel(); // goes "offline" within two minutes
    }
  }

  /// Whether [user] (a `users` document) is online now.
  static bool isOnline(Map<String, dynamic>? user, {DateTime? now}) {
    final at = DateTime.tryParse((user?['lastActiveAt'] ?? '').toString());
    if (at == null) return false;
    return (now ?? DateTime.now()).difference(at) < onlineWithin;
  }

  /// "Last seen 4:05 PM" / "Last seen 28/10" (empty if never seen).
  static String lastSeen(Map<String, dynamic>? user, {DateTime? now}) {
    final at = DateTime.tryParse((user?['lastActiveAt'] ?? '').toString());
    if (at == null) return '';
    now ??= DateTime.now();
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = '$h:${at.minute.toString().padLeft(2, '0')} '
        '${at.hour < 12 ? 'AM' : 'PM'}';
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return 'Last seen ${sameDay ? time : '${at.day}/${at.month}'}';
  }

  /// The other person's `users` document, live.
  static Stream<Map<String, dynamic>?> user(String uid) => AppDatabase.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.data());
}
