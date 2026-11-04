import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/firestore_service.dart';

/// No provider (doctor, nurse, technician, therapist) can start a visit with
/// the OTP before its booked time.
void main() {
  final at630 = DateTime(2026, 10, 13, 18, 30);
  final at700 = DateTime(2026, 10, 13, 19, 0);

  Map<String, dynamic> booking(String time,
          {bool urgent = false, String date = '13/10/2026', int? days}) =>
      {
        'date': date,
        'time': time,
        'isUrgentEmergency': urgent,
        if (days != null) 'durationDays': days,
      };

  test('a 7 PM visit cannot start at 6:30, but can at 7', () {
    for (final time in ['07:00 PM', '07:00 PM - 08:00 PM']) {
      expect(FirestoreService.earlyStartMessage(booking(time), now: at630),
          contains('starts at 07:00 PM'));
      expect(FirestoreService.earlyStartMessage(booking(time), now: at700),
          isNull);
    }
  });

  test('a same-day urgent nurse / therapy visit with a chosen time too', () {
    expect(
        FirestoreService.earlyStartMessage(
            booking('07:00 PM', urgent: true),
            now: at630,
            what: 'session'),
        contains('This session starts at 07:00 PM'));
  });

  test('ASAP bookings start at once', () {
    expect(
        FirestoreService.earlyStartMessage(
            booking('ASAP (Immediate)', urgent: true),
            now: at630),
        isNull);
  });

  test('"11:00 AM - 12:00 PM" starts at 11 AM', () {
    final start = FirestoreService.bookedStart(booking('11:00 AM - 12:00 PM'),
        now: at630);
    expect(start, DateTime(2026, 10, 13, 11, 0));
  });

  test('multi-day nursing: each day from that day\'s start time', () {
    final multi = booking('12:00 PM - 06:00 PM Daily',
        date: '12/10/2026', days: 3);
    // day 2 at 11:30 AM: not yet
    expect(
        FirestoreService.earlyStartMessage(multi,
            now: DateTime(2026, 10, 13, 11, 30)),
        isNotNull);
    // day 2 at 12:05 PM: fine
    expect(
        FirestoreService.earlyStartMessage(multi,
            now: DateTime(2026, 10, 13, 12, 5)),
        isNull);
  });
}
