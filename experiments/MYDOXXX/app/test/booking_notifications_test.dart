import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/firestore_service.dart';

void main() {
  final booking = {
    'appointmentId': 'a1',
    'patientUid': 'pat1',
    'doctorUid': 'doc1',
    'patientName': 'Mia',
    'doctorName': 'Dr. Rao',
    'status': 'Confirmed',
    'date': '12/10/2026',
    'time': '08:00 PM - 09:00 PM',
    'createdAt': '2026-10-10T09:00:00.000',
  };

  test('doctor is notified about a newly booked appointment', () {
    final events = FirestoreService.bookingNotifications([booking],
        uid: 'doc1', forPatient: false);
    expect(events.any((e) => e['kind'] == 'booked' && e['title']!.contains('Mia')),
        isTrue);
  });

  test('another doctor does not get it', () {
    final events = FirestoreService.bookingNotifications([booking],
        uid: 'doc2', forPatient: false);
    expect(events.where((e) => e['kind'] == 'booked'), isEmpty);
  });

  test('patient is told the booking is confirmed', () {
    final events = FirestoreService.bookingNotifications([booking],
        uid: 'pat1', forPatient: true);
    expect(events.any((e) => e['kind'] == 'accepted'), isTrue);
  });
}
