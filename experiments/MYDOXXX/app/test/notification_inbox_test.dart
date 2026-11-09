import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/notification_inbox.dart';
import 'package:mydox/utils/ist_timestamp.dart';

Map<String, String> item(String title, DateTime at) =>
    {'kind': '', 'title': title, 'body': '', 'at': at.toIso8601String()};

void main() {
  final t = DateTime(2026, 10, 27, 10);

  test('saved notifications and screen events make one list, newest first',
      () {
    final list = NotificationInbox.merge(
      [item('Duty assigned', t.add(const Duration(hours: 1)))],
      [item('Booking accepted', t), item('Running late', t.add(const Duration(hours: 2)))],
    );
    expect(list.map((e) => e['title']),
        ['Running late', 'Duty assigned', 'Booking accepted']);
  });

  test('an event and its push (same moment) show once, as the push', () {
    final list = NotificationInbox.merge(
      [item('Booking confirmed ✅', t.add(const Duration(seconds: 20)))],
      [item('Dr. Asha accepted your booking', t)],
    );
    expect(list.map((e) => e['title']), ['Booking confirmed ✅']);
  });

  test('a saved document becomes a bell item with its time', () {
    final e = NotificationInbox.fromDoc('n1', {
      'title': 'Doctor no-show',
      'body': 'Dr. Rao did not arrive',
      'type': 'care_shift',
      'createdAt': timestampOf(t),
    });
    expect(e['id'], 'push:n1');
    expect(e['title'], 'Doctor no-show');
    expect(e['kind'], 'care_shift');
    expect(DateTime.parse(e['at']!), t);
  });
}
