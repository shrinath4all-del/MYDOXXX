import 'app_database.dart';
import '../utils/ist_clock.dart';
import '../utils/ist_timestamp.dart';

/// Every notification sent to an account (care physician duties, bookings,
/// SOS, nurse shifts, agency requests …) is saved by the push Cloud Function
/// in `users/{uid}/notifications`, so the bell of every login lists it, even
/// when the push never reached a phone. Chat messages are not saved there
/// (the Chat tab lists them).
class NotificationInbox {
  NotificationInbox._();

  static const int limit = 50;

  /// Saved notifications, newest first, in the bell's item shape
  /// ({id, kind, title, body, at}).
  static Stream<List<Map<String, String>>> stream(String uid) {
    try {
      return AppDatabase.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => [for (final d in s.docs) fromDoc(d.id, d.data())]);
    } catch (_) {
      return Stream.value(const []); // no Firebase (tests)
    }
  }

  static Map<String, String> fromDoc(String id, Map<String, dynamic> d) {
    final at = d['createdAt'];
    final when = istTimeOf(at) ?? IstClock.now();
    return {
      'id': 'push:$id',
      'kind': (d['type'] ?? '').toString(),
      'title': (d['title'] ?? '').toString(),
      'body': (d['body'] ?? '').toString(),
      'at': when.toIso8601String(),
    };
  }

  /// One list for the bell: the saved notifications plus the screen's own
  /// events (reminders worked out on the phone, and anything from before the
  /// list was saved). An event within [_same] of a saved notification is the
  /// same happening (the push is sent the moment it changes) and shows once.
  static List<Map<String, String>> merge(
      List<Map<String, String>> saved, List<Map<String, String>> events) {
    final savedTimes = [
      for (final s in saved) IstClock.tryParse(s['at'] ?? ''),
    ].whereType<DateTime>().toList();
    final out = [
      ...saved,
      for (final e in events)
        if (!_matches(IstClock.tryParse(e['at'] ?? ''), savedTimes)) e,
    ];
    out.sort((a, b) => _time(b).compareTo(_time(a)));
    return out;
  }

  static const Duration _same = Duration(minutes: 2);

  static bool _matches(DateTime? at, List<DateTime> times) =>
      at != null && times.any((t) => t.difference(at).abs() <= _same);

  static DateTime _time(Map<String, String> e) =>
      IstClock.tryParse(e['at'] ?? '') ?? DateTime(2000);
}
