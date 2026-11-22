import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_duty_service.dart';
import 'package:mydox/services/notification_inbox.dart';
import 'package:mydox/services/nurse_duty_service.dart';

void main() {
  final now = DateTime(2026, 11, 21, 10);
  final shifts = [
    {'id': 'a', 'status': 'claimed', 'date': '2026-11-25', 'start': '08:00', 'end': '14:00', 'postedBy': 'hospital'},
    {'id': 'b', 'status': 'pending_agency', 'date': '2026-12-01', 'start': '20:00', 'end': '08:00', 'postedBy': 'hospital'},
    // already done, cancelled, or on duty now: left alone
    {'id': 'c', 'status': 'completed', 'date': '2026-11-10', 'start': '08:00', 'end': '14:00', 'postedBy': 'hospital'},
    {'id': 'd', 'status': 'cancelled', 'date': '2026-11-26', 'start': '08:00', 'end': '14:00', 'postedBy': 'hospital'},
    {'id': 'e', 'status': 'claimed', 'date': '2026-11-21', 'start': '08:00', 'end': '14:00', 'postedBy': 'hospital'},
    // a patient's home visit is not a locum shift
    {'id': 'f', 'status': 'claimed', 'date': '2026-11-27', 'start': '10:00', 'end': '12:00', 'postedBy': 'patient', 'slot': 'visit'},
  ];

  test('placed full time: every upcoming locum shift is released', () {
    expect(upcomingLocumShiftIds(shifts, now), ['a', 'b']);
  });

  test('nurse placed full time: every upcoming locum shift is released', () {
    expect(upcomingNurseLocumShiftIds(shifts, now), ['a', 'b']);
  });

  test('a new-shift notice already seen leaves the bell, updates stay', () {
    final readAt = DateTime(2026, 11, 21, 9);
    final events = [
      {'title': 'New shift open', 'body': '', 'at': '2026-11-21T08:00:00'},
      {'title': '🚨 Urgent shift open', 'body': '', 'at': '2026-11-21T09:30:00'},
      {'title': '🏠 New home visit', 'body': '', 'at': '2026-11-20T08:00:00'},
      {'title': 'Shift booked at Lokmanya Hospital', 'body': '', 'at': '2026-11-21T08:00:00'},
    ];
    expect(
        NotificationInbox.withoutSeenOffers(events, readAt).map((e) => e['title']),
        ['🚨 Urgent shift open', 'Shift booked at Lokmanya Hospital']);
    // never opened: everything shows
    expect(NotificationInbox.withoutSeenOffers(events, null).length, 4);
  });
}
