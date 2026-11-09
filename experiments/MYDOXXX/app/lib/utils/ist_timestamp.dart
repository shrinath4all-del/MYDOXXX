import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'ist_clock.dart';

/// Firestore `Timestamp` <-> India time. The only place besides `ist_clock.dart`
/// that may call `Timestamp.toDate()` / `Timestamp.fromDate()` (guarded by
/// `test/ist_clock_guard_test.dart`). See `ist_clock.dart` for the one rule:
/// a plain DateTime is India wall-clock time, a UTC-flagged one is a real instant.
extension IstTimestamp on Timestamp {
  /// The India wall-clock time of this stored instant.
  DateTime toIst() => IstClock.fromInstant(toDate());

  /// This stored instant as a UTC-flagged real instant.
  DateTime toInstant() => IstClock.instantOf(toDate());
}

/// A Firestore Timestamp for [t]: a plain value is an India wall-clock time
/// (shift and slot times); a UTC-flagged value is already a real instant.
Timestamp timestampOf(DateTime t) => Timestamp.fromDate(IstClock.toInstant(t));

/// A stored time in any of the forms the app keeps it (Firestore Timestamp,
/// DateTime, or ISO text) as an India wall-clock time, or null if missing or
/// not a date.
DateTime? istTimeOf(dynamic raw) {
  if (raw is Timestamp) return raw.toIst();
  if (raw is DateTime) return IstClock.wall(raw);
  return IstClock.tryParse((raw ?? '').toString());
}
