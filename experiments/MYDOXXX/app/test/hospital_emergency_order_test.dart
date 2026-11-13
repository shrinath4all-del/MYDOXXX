import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/sos_service.dart';

/// The hospital's emergency lists (Active Admissions, Emergency History) show
/// the newest emergency on top and the oldest at the bottom.
void main() {
  List<String> ids(List<Map<String, dynamic>> list) =>
      [for (final e in list) e['appointmentId'].toString()];

  test('newest on top, oldest at the bottom', () {
    final list = SosService.newestFirst([
      {'appointmentId': 'morning', 'createdAt': '2026-11-13T09:00:00'},
      {'appointmentId': 'evening', 'createdAt': '2026-11-13T18:30:00'},
      {'appointmentId': 'yesterday', 'createdAt': '2026-11-12T23:59:00'},
      {'appointmentId': 'noon', 'createdAt': '2026-11-13T12:00:00'},
    ]);
    expect(ids(list), ['evening', 'noon', 'morning', 'yesterday']);
  });

  test('server timestamps and text times sort together', () {
    final list = SosService.newestFirst([
      {'appointmentId': 'text 10:00', 'createdAt': '2026-11-13T10:00:00'},
      {
        'appointmentId': 'stamp 11:00',
        // 05:30 UTC is 11:00 India time
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 13, 5, 30)),
      },
      {'appointmentId': 'text 09:00', 'createdAt': '2026-11-13T09:00:00'},
    ]);
    expect(ids(list), ['stamp 11:00', 'text 10:00', 'text 09:00']);
  });

  test('missing start time uses the last update, else goes last', () {
    final list = SosService.newestFirst([
      {'appointmentId': 'no time'},
      {'appointmentId': 'updated', 'updatedAt': '2026-11-13T15:00:00'},
      {'appointmentId': 'created', 'createdAt': '2026-11-13T14:00:00'},
    ]);
    expect(ids(list), ['updated', 'created', 'no time']);
  });

  test('equal times keep a stable order and the input is not changed', () {
    final input = [
      {'appointmentId': 'b', 'createdAt': '2026-11-13T10:00:00'},
      {'appointmentId': 'a', 'createdAt': '2026-11-13T10:00:00'},
    ];
    expect(ids(SosService.newestFirst(input)), ['a', 'b']);
    expect(ids(input), ['b', 'a']);
  });
}
