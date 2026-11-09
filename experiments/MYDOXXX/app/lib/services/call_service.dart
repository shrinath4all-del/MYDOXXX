import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ist_clock.dart';

/// Firestore signalling for WebRTC video calls (WhatsApp-style: the caller
/// rings the other side, who can accept or decline).
///
/// calls/{callId}
///   callerUid, callerName, calleeUid, calleeName, appointmentId,
///   status: ringing | active | declined | ended | missed,
///   offer / answer: {sdp, type}, createdAt
///   callerCandidates/*, calleeCandidates/*  (ICE candidates)
class CallService {
  static final _db = AppDatabase.instance;

  /// Public STUN servers. Add a TURN server here for users behind strict NATs.
  static const Map<String, dynamic> rtcConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
    ],
  };

  /// How long a call rings before it counts as missed.
  static const Duration ringTimeout = Duration(seconds: 45);

  static DocumentReference<Map<String, dynamic>> callRef(String callId) =>
      _db.collection('calls').doc(callId);

  static CollectionReference<Map<String, dynamic>> candidates(
          String callId, bool fromCaller) =>
      callRef(callId).collection(fromCaller ? 'callerCandidates' : 'calleeCandidates');

  static String newCallId(String appointmentId) =>
      '${appointmentId}_${IstClock.instant().millisecondsSinceEpoch}';

  static Future<void> setStatus(String callId, String status) async {
    try {
      await callRef(callId).update({
        'status': status,
        'updatedAt': IstClock.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Calls currently ringing for [uid].
  static Stream<QuerySnapshot<Map<String, dynamic>>> incomingCalls(String uid) {
    return _db
        .collection('calls')
        .where('calleeUid', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots();
  }

  /// A ringing call older than [ringTimeout] is stale (caller gave up).
  static bool isStale(Map<String, dynamic> call) {
    final created = IstClock.tryParse((call['createdAt'] ?? '').toString());
    return created == null || IstClock.now().difference(created) > ringTimeout;
  }

  /// Removes the finished call and its ICE candidates so nothing is kept.
  static Future<void> cleanup(String callId) async {
    try {
      for (final fromCaller in [true, false]) {
        final snap = await candidates(callId, fromCaller).get();
        for (final d in snap.docs) {
          await d.reference.delete();
        }
      }
      await callRef(callId).delete();
    } catch (_) {}
  }
}
