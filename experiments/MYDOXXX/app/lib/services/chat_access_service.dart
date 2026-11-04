import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/appointment_rules.dart';
import '../utils/chat_access.dart';
import '../utils/safe_cast.dart';

/// Reads and enforces the chat rules (see [ChatAccess]) and the recharge
/// plans / wallet that go with them.
class ChatAccessService {
  ChatAccessService._();

  static FirebaseFirestore get _db => AppDatabase.instance;

  /// The chat id is the patient uid and the provider uid joined by "_".
  static ({String patientUid, String providerUid})? parties(String chatId) {
    final p = chatId.split('_');
    if (p.length != 2 || p[0].isEmpty || p[1].isEmpty) return null;
    return (patientUid: p[0], providerUid: p[1]);
  }

  /// When the latest finished consultation between the two ended, or null if
  /// none has: that is when chat opens.
  static Future<DateTime?> consultationEnd(
      String patientUid, String providerUid) async {
    final snap = await _db
        .collection('appointments')
        .where('patientUid', isEqualTo: patientUid)
        .where('doctorUid', isEqualTo: providerUid)
        .get();
    DateTime? latest;
    for (final d in snap.docs) {
      final a = d.data();
      if (AppointmentRules.statusOf(a) != 'Completed') continue;
      final t = DateTime.tryParse((a['completedAt'] ?? '').toString()) ??
          AppointmentRules.end(a) ??
          AppointmentRules.start(a);
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  static Stream<Map<String, dynamic>?> chatDoc(String chatId) =>
      _db.collection('chats').doc(chatId).snapshots().map((d) => d.data());

  /// Sends one message. A picture / PDF / audio / video with its description
  /// is ONE message ([text] is the description); sending them separately is
  /// two.
  ///
  /// The patient's message is counted and refused when the chat is closed or
  /// the messages are used (throws [ChatClosedException]). The provider is
  /// not limited while the chat time is on; after it, the provider can send
  /// one follow-up message.
  ///
  /// Ambulance chat ([ambulanceSosId] set): open only while the ambulance is
  /// on duty for the patient ([ambulanceOnDuty]); nothing is counted.
  static Future<void> send({
    required String chatId,
    required String senderUid,
    required String senderName,
    required DateTime? consultationEnd,
    String type = 'text',
    String text = '',
    String? mediaUrl,
    String? fileName,
    String? ambulanceSosId,
    bool ambulanceOnDuty = false,
    Map<String, dynamic> extra = const {},
  }) async {
    final who = parties(chatId);
    final isPatient = who != null && who.patientUid == senderUid;
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final now = DateTime.now();

    if (ambulanceSosId != null) {
      if (!ambulanceOnDuty) throw ChatClosedException(ChatAccessState.offDuty);
      final batch = _db.batch();
      batch.set(msgRef, {
        ..._message(msgRef.id, senderUid, senderName, type, text, mediaUrl,
            fileName, now),
        ...extra,
      });
      batch.set(
          chatRef,
          {
            'lastMessage': _last(type, text),
            'updatedAt': now.toIso8601String(),
            'ambulanceSosId': ambulanceSosId,
            ...unreadFor(chatId, senderUid),
          },
          SetOptions(merge: true));
      await batch.commit();
      return;
    }

    if (consultationEnd == null) {
      throw ChatClosedException(ChatAccessState.notStarted);
    }
    await _db.runTransaction((tx) async {
      final chat = (await tx.get(chatRef)).data();
      final access = ChatAccess.compute(
          consultationEnd: consultationEnd, chat: chat, now: now);
      final followUp = !isPatient && access.providerCanFollowUp;
      if (isPatient
          ? !access.isOpen
          : !(access.providerCanSend || followUp)) {
        throw ChatClosedException(access.state);
      }
      final c = ChatAccess.counters(chat, consultationEnd);
      final used = c.used + (isPatient ? 1 : 0);

      tx.set(msgRef, {
        ..._message(msgRef.id, senderUid, senderName, type, text, mediaUrl,
            fileName, now),
        ...extra,
        if (followUp) 'followUp': true,
      });
      tx.set(
          chatRef,
          {
            'lastMessage': _last(type, text),
            'updatedAt': now.toIso8601String(),
            // the window these counters belong to
            'accessEpoch': consultationEnd.toIso8601String(),
            'patientMsgsUsed': used,
            'bonusMsgs': c.bonus,
            if (c.paidUntil != null) 'paidUntil': c.paidUntil!.toIso8601String(),
            'providerFollowUps': c.followUps + (followUp ? 1 : 0),
            if (followUp) 'followUpAt': now.toIso8601String(),
            ...unreadFor(chatId, senderUid),
          },
          SetOptions(merge: true));
    });
  }

  static Map<String, dynamic> _message(
          String id,
          String senderUid,
          String senderName,
          String type,
          String text,
          String? mediaUrl,
          String? fileName,
          DateTime now) =>
      {
        'messageId': id,
        'senderUid': senderUid,
        'senderName': senderName,
        'type': type,
        'text': text.trim(),
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (type != 'text') 'fileName': fileName ?? 'attachment',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': now.toIso8601String(),
      };

  /// The chat list's preview of a message.
  static String _last(String type, String text) {
    final t = text.trim();
    if (type == 'text') return t;
    final label = switch (type) {
      'prescription' => '💊 Prescription',
      'audio' => '🎵 Audio',
      'video' => '🎬 Video',
      'image' => '📷 Photo',
      _ => '📎 File',
    };
    return t.isEmpty ? label : '$label: $t';
  }

  // ---------------------------------------------------------- unread

  /// Adds one unread message for the other person in the chat (merged into
  /// the chat document): `unread: {uid: count}`.
  static Map<String, dynamic> unreadFor(String chatId, String senderUid) {
    final who = parties(chatId);
    if (who == null) return const {};
    final to =
        who.patientUid == senderUid ? who.providerUid : who.patientUid;
    return {
      'unread': {to: FieldValue.increment(1)},
    };
  }

  /// [uid] has read everything in the chat.
  static Future<void> markRead(String chatId, String uid) async {
    try {
      await _db.collection('chats').doc(chatId).set({
        'unread': {uid: 0},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Unread messages for [uid] in one chat.
  static int unreadOf(Map<String, dynamic>? chat, String uid) {
    final m = chat?['unread'];
    final v = m is Map ? m[uid] : null;
    return v is num && v > 0 ? v.toInt() : 0;
  }

  /// Unread messages for [uid] in one chat, live.
  static Stream<int> unreadCount(String chatId, String uid) =>
      chatDoc(chatId).map((c) => unreadOf(c, uid));

  /// How many chats have unread messages for [uid] (for the Chat tab).
  static Stream<int> unreadChats(String uid) {
    try {
      return _db
          .collection('chats')
          .where('unread.$uid', isGreaterThan: 0)
          .snapshots()
          .map((s) => s.size)
          .handleError((_) {});
    } catch (_) {
      return Stream.value(0); // no Firebase (tests)
    }
  }

  // ---------------------------------------------------- call requests

  /// The patient asks for an audio or video call. It shows in the chat for
  /// both; the provider starts the call from it (15 minutes at most). Not
  /// counted as a message.
  static Future<void> requestCall({
    required String chatId,
    required String senderUid,
    required String senderName,
    required bool video,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final now = DateTime.now().toIso8601String();
    final label = video ? 'Video call request' : 'Audio call request';
    final batch = _db.batch();
    batch.set(msgRef, {
      'messageId': msgRef.id,
      'senderUid': senderUid,
      'senderName': senderName,
      'type': 'call_request',
      'callType': video ? 'video' : 'audio',
      'callStatus': 'requested',
      'text': label,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': now,
    });
    batch.set(
        chatRef,
        {
          'lastMessage': '📞 $label',
          'updatedAt': now,
          ...unreadFor(chatId, senderUid),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  /// Moves a call request on: accepted, started, completed, missed,
  /// declined or cancelled.
  static Future<void> setCallStatus(
      String chatId, String messageId, String status,
      {int? seconds, String? callId}) async {
    try {
      await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'callStatus': status,
        '${status}At': DateTime.now().toIso8601String(),
        if (seconds != null) 'callSeconds': seconds,
        if (callId != null) 'callId': callId,
      });
    } catch (_) {} // the call itself goes on
  }

  // ---------------------------------------------------------- recharge

  static Stream<List<RechargePlan>> _allPlans() => _db
      .collection('chat_recharge_plans')
      .snapshots()
      .map((s) {
        final list = [
          for (final d in s.docs)
            if (d.data()['active'] != false)
              RechargePlan.fromMap(d.id, d.data())
        ]..removeWhere((p) => p.price <= 0 || p.days <= 0);
        list.sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  /// The paid chat plans (1 day, 3 days, 7 days..., 25 messages each), from
  /// Firestore.
  static Stream<List<RechargePlan>> plans() =>
      _allPlans().map((l) => [for (final p in l) if (!p.isSingle) p]);

  /// The single-message plan (₹200 for one message), or null if the admin
  /// has not added it.
  static Stream<RechargePlan?> singlePlan() => _allPlans().map((l) {
        for (final p in l) {
          if (p.isSingle) return p;
        }
        return null;
      });

  /// MedCoins in the patient's wallet (1 MedCoin = ₹1).
  static Stream<int> walletBalance(String patientUid) => _db
      .collection('wallets')
      .doc(patientUid)
      .snapshots()
      .map((d) => toNum(d.data()?['balance'])?.round() ?? 0);
}

class RechargePlan {
  final String id;
  final int days;
  final int price;
  final int messages;
  final int order;

  /// 'single' for the one-message plan, empty for the paid chat plans.
  final String kind;
  const RechargePlan(
      {required this.id,
      required this.days,
      required this.price,
      required this.messages,
      required this.order,
      this.kind = ''});

  bool get isSingle => kind == 'single';

  factory RechargePlan.fromMap(String id, Map<String, dynamic> m) =>
      RechargePlan(
        id: id,
        days: toNum(m['days'])?.toInt() ?? 0,
        price: toNum(m['price'])?.toInt() ?? 0,
        messages: toNum(m['messages'])?.toInt() ?? ChatAccess.paidMessages,
        order: toNum(m['order'])?.toInt() ?? 0,
        kind: (m['kind'] ?? '').toString(),
      );

  String get label => days == 1 ? '1 day' : '$days days';
}
