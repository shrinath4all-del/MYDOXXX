import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/chat_access.dart';

void main() {
  final end = DateTime(2026, 10, 26, 10);
  final epoch = end.toIso8601String();

  group('chat opens when the consultation ends', () {
    test('no finished consultation: not started', () {
      final a = ChatAccess.compute(consultationEnd: null, now: end);
      expect(a.state, ChatAccessState.notStarted);
      expect(a.isOpen, isFalse);
    });

    test('just after it ended: open with 10 free messages', () {
      final a = ChatAccess.compute(
          consultationEnd: end, now: end.add(const Duration(minutes: 1)));
      expect(a.state, ChatAccessState.open);
      expect(a.remaining, 10);
      expect(a.endsAt, end.add(const Duration(hours: 24)));
    });

    test('24 hours after it ended: time over, recharge needed', () {
      final a = ChatAccess.compute(
          consultationEnd: end, now: end.add(const Duration(hours: 24)));
      expect(a.state, ChatAccessState.timeOver);
      expect(a.needsRecharge, isTrue);
    });
  });

  group('the 10 free messages', () {
    test('9 used: still open, 1 left', () {
      final a = ChatAccess.compute(
        consultationEnd: end,
        chat: {'accessEpoch': epoch, 'patientMsgsUsed': 9},
        now: end.add(const Duration(hours: 1)),
      );
      expect(a.state, ChatAccessState.open);
      expect(a.remaining, 1);
    });

    test('10 used: limit reached, but the provider can still answer', () {
      final a = ChatAccess.compute(
        consultationEnd: end,
        chat: {'accessEpoch': epoch, 'patientMsgsUsed': 10},
        now: end.add(const Duration(hours: 1)),
      );
      expect(a.state, ChatAccessState.limitReached);
      expect(a.needsRecharge, isTrue);
      expect(a.providerCanSend, isTrue);
    });

    test('paid chat adds 25 messages and time', () {
      final paid = end.add(const Duration(days: 3));
      final a = ChatAccess.compute(
        consultationEnd: end,
        chat: {
          'accessEpoch': epoch,
          'patientMsgsUsed': 10,
          'bonusMsgs': ChatAccess.paidMessages,
          'paidUntil': paid.toIso8601String(),
        },
        now: end.add(const Duration(hours: 30)),
      );
      expect(a.state, ChatAccessState.open);
      expect(a.limit, 35);
      expect(a.remaining, 25);
      expect(a.endsAt, paid);
    });

    test('provider cannot chat once the time is over', () {
      final a = ChatAccess.compute(
          consultationEnd: end, now: end.add(const Duration(hours: 25)));
      expect(a.providerCanSend, isFalse);
    });
  });

  group('single message after the consultation', () {
    test('after the chat time the doctor can send one follow-up', () {
      final a = ChatAccess.compute(
          consultationEnd: end, now: end.add(const Duration(hours: 25)));
      expect(a.providerCanFollowUp, isTrue);
    });

    test('only one follow-up; the patient sees when it was sent', () {
      final sent = end.add(const Duration(hours: 26));
      final a = ChatAccess.compute(
        consultationEnd: end,
        chat: {
          'accessEpoch': epoch,
          'providerFollowUps': 1,
          'followUpAt': sent.toIso8601String(),
        },
        now: end.add(const Duration(hours: 27)),
      );
      expect(a.providerCanFollowUp, isFalse);
      expect(a.followUpAt, sent);
      expect(a.state, ChatAccessState.timeOver);
    });

    test('paying for a single message opens the chat for one message', () {
      final now = end.add(const Duration(hours: 27));
      final a = ChatAccess.compute(
        consultationEnd: end,
        chat: {
          'accessEpoch': epoch,
          'patientMsgsUsed': 10,
          'bonusMsgs': 1,
          'paidUntil': now.add(const Duration(days: 1)).toIso8601String(),
        },
        now: now,
      );
      expect(a.state, ChatAccessState.open);
      expect(a.remaining, 1);
    });
  });

  group('ambulance chat', () {
    const amb = 'amb1';
    test('open only while the ambulance is on duty for the patient', () {
      for (final status in ['Ambulance Dispatched', 'Patient Picked Up']) {
        expect(
            ChatAccess.ambulanceOnDuty(
                {'assignedAmbulanceUid': amb, 'status': status}, amb),
            isTrue,
            reason: status);
      }
      for (final status in ['Pending Ambulance Dispatch', 'In Progress', 'Completed']) {
        expect(
            ChatAccess.ambulanceOnDuty(
                {'assignedAmbulanceUid': amb, 'status': status}, amb),
            isFalse,
            reason: status);
      }
      expect(
          ChatAccess.ambulanceOnDuty(
              {'assignedAmbulanceUid': 'other', 'status': 'Ambulance Dispatched'},
              amb),
          isFalse);
    });

    test('off duty: closed, with no recharge', () {
      final off = ChatAccess.ambulance(onDuty: false);
      expect(off.state, ChatAccessState.offDuty);
      expect(off.isOpen, isFalse);
      expect(off.needsRecharge, isFalse);
      expect(ChatClosedException(off.state).toString(), contains('off duty'));
      expect(ChatAccess.ambulance(onDuty: true).isOpen, isTrue);
    });
  });

  group('a new consultation starts a new window', () {
    test('counters of the earlier consultation do not carry over', () {
      final later = end.add(const Duration(days: 5));
      final a = ChatAccess.compute(
        consultationEnd: later,
        chat: {
          'accessEpoch': epoch, // the earlier one
          'patientMsgsUsed': 10,
          'bonusMsgs': 25,
          'providerFollowUps': 1,
          'paidUntil': end.add(const Duration(days: 9)).toIso8601String(),
        },
        now: later.add(const Duration(hours: 1)),
      );
      expect(a.state, ChatAccessState.open);
      expect(a.remaining, 10);
      expect(a.followUpsUsed, 0);
      expect(a.endsAt, later.add(const Duration(hours: 24)));
    });
  });
}
