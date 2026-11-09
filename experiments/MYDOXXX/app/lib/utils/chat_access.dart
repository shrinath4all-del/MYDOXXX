import 'dart:math' as math;
import 'ist_clock.dart';

/// Why a chat can or cannot be used right now.
enum ChatAccessState {
  /// The consultation has not ended yet: chat opens when it does.
  notStarted,

  /// The chat is open.
  open,

  /// 24 hours after the consultation (or the paid time) are over.
  timeOver,

  /// The patient used all their messages for this chat window.
  limitReached,

  /// Ambulance chat: the ambulance is not on duty for this patient (not
  /// dispatched to them, or the patient was already handed over).
  offDuty,
}

/// The chat rules for one patient and one provider.
///
///   * Chat opens when the consultation ends, and stays open for 24 hours.
///   * Free chat: the patient may send [baseMessages] messages in that window.
///     A picture, PDF, audio or video sent together with its description is
///     one message; sent separately they are two. The provider's messages
///     are not counted.
///   * Paid chat: when the 24 hours or the messages run out the patient can
///     recharge; a plan adds days and 25 messages (see ChatAccessService).
///   * Single message: after the chat time is over the doctor may send ONE
///     follow-up message ("How are you?"), and the patient can pay for one
///     message (₹200, the `single` plan) to write to the doctor.
///   * Ambulance chat is the exception: open only while the ambulance is on
///     duty for the patient, with no message limit (see [ChatAccess.ambulance]).
///
/// What is saved on `chats/{chatId}`:
///   accessEpoch       when the consultation that opened this window ended
///   patientMsgsUsed   messages the patient has sent in this window
///   bonusMsgs         messages added by recharges in this window
///   paidUntil         end of the paid time (ISO), if recharged
///   providerFollowUps follow-up messages the provider sent after the time
///   followUpAt        when the provider's follow-up was sent (ISO)
/// A new consultation (a later end time) starts a fresh window.
class ChatAccess {
  static const int baseMessages = 10;
  static const int paidMessages = 25;
  static const Duration baseWindow = Duration(hours: 24);

  /// Follow-up messages the provider may send after the chat time is over.
  static const int followUpsAllowed = 1;

  final ChatAccessState state;

  /// When the chat time ends (null before the consultation ends).
  final DateTime? endsAt;
  final int used;
  final int limit;

  /// Follow-ups the provider already sent after the chat time.
  final int followUpsUsed;

  /// When the provider's follow-up was sent (null: none).
  final DateTime? followUpAt;

  const ChatAccess(this.state,
      {this.endsAt,
      this.used = 0,
      this.limit = baseMessages,
      this.followUpsUsed = 0,
      this.followUpAt});

  /// Ambulance chat: open while the ambulance is on duty for the patient.
  factory ChatAccess.ambulance({required bool onDuty}) => ChatAccess(
      onDuty ? ChatAccessState.open : ChatAccessState.offDuty,
      limit: 0);

  /// The ambulance is on duty for this SOS: dispatched to the patient, until
  /// the patient is handed over at the hospital.
  static bool ambulanceOnDuty(Map<String, dynamic>? sos, String? ambulanceUid) =>
      sos != null &&
      ambulanceUid != null &&
      sos['assignedAmbulanceUid'] == ambulanceUid &&
      const {'Ambulance Dispatched', 'Patient Picked Up'}
          .contains(sos['status']);

  int get remaining => math.max(0, limit - used);
  bool get isOpen => state == ChatAccessState.open;

  /// The patient can no longer write, and can recharge.
  bool get needsRecharge =>
      state == ChatAccessState.timeOver ||
      state == ChatAccessState.limitReached;

  /// The provider answers while the chat time is on, even after the
  /// patient used all their messages.
  bool get providerCanSend =>
      state == ChatAccessState.open || state == ChatAccessState.limitReached;

  /// After the chat time the provider can still send one follow-up message.
  bool get providerCanFollowUp =>
      state == ChatAccessState.timeOver && followUpsUsed < followUpsAllowed;

  /// The chat time is on (calls can be requested and started).
  bool get timeOn => providerCanSend;

  /// The counters saved for this window: from the chat document, or zero if
  /// the document belongs to an earlier consultation.
  static ({
    int used,
    int bonus,
    DateTime? paidUntil,
    int followUps,
    DateTime? followUpAt
  }) counters(Map<String, dynamic>? chat, DateTime consultationEnd) {
    final epoch = IstClock.tryParse((chat?['accessEpoch'] ?? '').toString());
    final sameWindow = epoch != null &&
        epoch.millisecondsSinceEpoch == consultationEnd.millisecondsSinceEpoch;
    if (!sameWindow) {
      return (
        used: 0,
        bonus: 0,
        paidUntil: null,
        followUps: 0,
        followUpAt: null
      );
    }
    return (
      used: _int(chat?['patientMsgsUsed']),
      bonus: _int(chat?['bonusMsgs']),
      paidUntil: IstClock.tryParse((chat?['paidUntil'] ?? '').toString()),
      followUps: _int(chat?['providerFollowUps']),
      followUpAt: IstClock.tryParse((chat?['followUpAt'] ?? '').toString()),
    );
  }

  /// Works out the state of the chat.
  /// [consultationEnd]: when the latest consultation between the two ended
  /// (null: none has ended).
  static ChatAccess compute({
    required DateTime? consultationEnd,
    Map<String, dynamic>? chat,
    DateTime? now,
  }) {
    now ??= IstClock.now();
    if (consultationEnd == null) {
      return const ChatAccess(ChatAccessState.notStarted);
    }
    final c = counters(chat, consultationEnd);
    var end = consultationEnd.add(baseWindow);
    if (c.paidUntil != null && c.paidUntil!.isAfter(end)) end = c.paidUntil!;
    final limit = baseMessages + c.bonus;
    final state = !now.isBefore(end)
        ? ChatAccessState.timeOver
        : c.used >= limit
            ? ChatAccessState.limitReached
            : ChatAccessState.open;
    return ChatAccess(state,
        endsAt: end,
        used: c.used,
        limit: limit,
        followUpsUsed: c.followUps,
        followUpAt: c.followUpAt);
  }

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
}

/// Thrown when a message cannot be sent because the chat is closed.
class ChatClosedException implements Exception {
  final ChatAccessState state;
  ChatClosedException(this.state);

  @override
  String toString() => switch (state) {
        ChatAccessState.notStarted =>
          'Chat opens when the consultation ends.',
        ChatAccessState.timeOver => 'The chat time is over.',
        ChatAccessState.limitReached =>
          'You have used all your messages for this chat.',
        ChatAccessState.offDuty =>
          'Chat is unavailable: the ambulance is off duty.',
        ChatAccessState.open => 'The chat is open.',
      };
}
