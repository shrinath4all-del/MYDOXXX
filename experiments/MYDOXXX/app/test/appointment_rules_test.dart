import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/appointment_rules.dart';

Map<String, dynamic> appt(String date, String time,
        {String status = 'Confirmed', Map<String, dynamic> extra = const {}}) =>
    {'date': date, 'time': time, 'status': status, ...extra};

void main() {
  videoWindowTests();
  // "now" = 7 Oct 2026, 11:30
  final now = DateTime(2026, 10, 7, 11, 30);

  test('upcoming shows today and tomorrow, not the day after', () {
    expect(AppointmentRules.isUpcoming(appt('7/10/2026', '08:00 PM - 09:00 PM'), now: now), isTrue);
    expect(AppointmentRules.isUpcoming(appt('8/10/2026', '10:00 AM - 11:00 AM'), now: now), isTrue);
    expect(AppointmentRules.isUpcoming(appt('9/10/2026', '10:00 AM - 11:00 AM'), now: now), isFalse);
  });

  test('slots that already ended are not upcoming, running ones are', () {
    expect(AppointmentRules.isUpcoming(appt('7/10/2026', '09:00 AM - 10:00 AM'), now: now), isFalse);
    expect(AppointmentRules.isMissed(appt('7/10/2026', '09:00 AM - 10:00 AM'), now: now), isTrue);
    // 11:00-12:00 is running at 11:30
    expect(AppointmentRules.isUpcoming(appt('7/10/2026', '11:00 AM - 12:00 PM'), now: now), isTrue);
  });

  test('a booking after tomorrow is neither missed nor history', () {
    final later = appt('15/10/2026', '10:00 AM - 11:00 AM');
    expect(AppointmentRules.isLater(later, now: now), isTrue);
    expect(AppointmentRules.isMissed(later, now: now), isFalse);
    expect(AppointmentRules.isHistory(later, now: now), isFalse);
    expect(AppointmentRules.isHistory(appt('7/10/2026', '09:00 AM - 10:00 AM'), now: now), isTrue);
  });

  test('finished appointments are never upcoming', () {
    expect(AppointmentRules.isUpcoming(appt('7/10/2026', '08:00 PM - 09:00 PM', status: 'Completed'), now: now), isFalse);
  });

  test('earliest first: 10-11 before 12-1', () {
    final list = [
      appt('8/10/2026', '12:00 PM - 01:00 PM'),
      appt('8/10/2026', '10:00 AM - 11:00 AM'),
      appt('7/10/2026', '08:00 PM - 09:00 PM'),
    ]..sort(AppointmentRules.compareByStart);
    expect(list.map((a) => a['time']).toList(),
        ['08:00 PM - 09:00 PM', '10:00 AM - 11:00 AM', '12:00 PM - 01:00 PM']);
  });

  test('urgent and SOS stay in upcoming while active; calendar categories', () {
    final urgent = appt('1/10/2026', 'ASAP (Immediate)', extra: {'isUrgentEmergency': true});
    final sos = appt('1/10/2026', 'ASAP (Immediate SOS)',
        extra: {'isUrgentEmergency': true, 'consultationType': AppointmentRules.sosType});
    expect(AppointmentRules.isUpcoming(urgent, now: now), isTrue);
    expect(AppointmentRules.isUpcoming(sos, now: now), isTrue);
    expect(AppointmentRules.category(urgent), 'urgent');
    expect(AppointmentRules.category(sos), 'sos');
    expect(AppointmentRules.category(appt('7/10/2026', '10:00 AM - 11:00 AM', status: 'Completed')), 'completed');
    expect(AppointmentRules.category(appt('7/10/2026', '10:00 AM - 11:00 AM')), 'pending');
    expect(AppointmentRules.dateKey(appt('7/10/2026', 'x')), '2026-10-07');
  });
}

void videoWindowTests() {
  group('video call window', () {
    final slot = {
      'date': '12/10/2026',
      'time': '07:00 PM - 08:00 PM',
      'status': 'Confirmed',
      'consultationType': 'Online',
    };

    test('never before the slot starts', () {
      final w = AppointmentRules.videoWindow(slot, now: DateTime(2026, 10, 12, 18, 59));
      expect(w.open, isFalse);
      expect(w.message, contains('07:00 PM'));
    });

    test('anytime from 7 to 8 pm, and it ends at 8 pm', () {
      for (final t in [DateTime(2026, 10, 12, 19, 0), DateTime(2026, 10, 12, 19, 40), DateTime(2026, 10, 12, 19, 59)]) {
        final w = AppointmentRules.videoWindow(slot, now: t);
        expect(w.open, isTrue, reason: '$t');
        expect(w.end, DateTime(2026, 10, 12, 20, 0));
      }
    });

    test('closed once the slot has ended', () {
      final w = AppointmentRules.videoWindow(slot, now: DateTime(2026, 10, 12, 20, 0));
      expect(w.open, isFalse);
      expect(w.message, contains('08:00 PM'));
    });
  });
}
