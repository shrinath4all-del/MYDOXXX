import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/ist_clock.dart';

/// Every expectation is a fixed India time or a fixed UTC instant, so the whole
/// file must give the same result under any machine time zone (run it with
/// TZ=UTC, TZ=Asia/Kolkata, TZ=America/New_York, TZ=Pacific/Auckland ...).
List<int> fields(DateTime t) =>
    [t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond];

void main() {
  tearDown(() => IstClock.debugSetInstantSource(null));

  // 18:45 UTC on 9 Nov 2026 is 00:15 on 10 Nov in India.
  final instantA = DateTime.utc(2026, 11, 9, 18, 45, 30, 250);
  void freeze(DateTime instant) => IstClock.debugSetInstantSource(() => instant);

  group('now() and instant()', () {
    test('now() is the India wall-clock time of the device clock', () {
      freeze(instantA);
      expect(fields(IstClock.now()), [2026, 11, 10, 0, 15, 30, 250]);
    });

    test('now() is a plain value, instant() is a UTC-flagged real instant', () {
      freeze(instantA);
      expect(IstClock.now().isUtc, isFalse);
      expect(IstClock.instant().isUtc, isTrue);
      expect(IstClock.instant(), instantA);
    });

    test('now() follows the day boundary in India, not in UTC', () {
      freeze(DateTime.utc(2026, 11, 9, 18, 29, 59)); // 23:59:59 IST, 9 Nov
      expect(IstClock.now().day, 9);
      freeze(DateTime.utc(2026, 11, 9, 18, 30)); // 00:00:00 IST, 10 Nov
      expect(fields(IstClock.now()).sublist(0, 6), [2026, 11, 10, 0, 0, 0]);
    });

    test('now() crosses the year boundary in India', () {
      freeze(DateTime.utc(2026, 12, 31, 18, 30));
      expect(fields(IstClock.now()).sublist(0, 5), [2027, 1, 1, 0, 0]);
    });

    test('the real clock is used when nothing is frozen', () {
      final a = IstClock.now();
      final b = IstClock.fromInstant(DateTime.now());
      expect(a.difference(b).abs() < const Duration(seconds: 5), isTrue);
    });
  });

  group('fromInstant / toInstant / fieldsToInstant / wall', () {
    test('fromInstant gives the same India time for a UTC or a local instant', () {
      final utc = DateTime.utc(2026, 11, 9, 4, 30);
      expect(fields(IstClock.fromInstant(utc)), [2026, 11, 9, 10, 0, 0, 0]);
      expect(fields(IstClock.fromInstant(utc.toLocal())),
          [2026, 11, 9, 10, 0, 0, 0]);
    });

    test('10:00 India is 04:30 UTC', () {
      expect(IstClock.fieldsToInstant(DateTime(2026, 11, 9, 10)),
          DateTime.utc(2026, 11, 9, 4, 30));
      expect(IstClock.toInstant(DateTime(2026, 11, 9, 10)),
          DateTime.utc(2026, 11, 9, 4, 30));
    });

    test('toInstant leaves a real instant alone; fieldsToInstant ignores the flag', () {
      final instant = DateTime.utc(2026, 11, 9, 4, 30);
      expect(IstClock.toInstant(instant), instant);
      expect(IstClock.fieldsToInstant(DateTime.utc(2026, 11, 9, 10)),
          IstClock.fieldsToInstant(DateTime(2026, 11, 9, 10)));
    });

    test('00:15 India belongs to the previous UTC day', () {
      expect(IstClock.toInstant(DateTime(2026, 11, 10, 0, 15)),
          DateTime.utc(2026, 11, 9, 18, 45));
    });

    test('an instant survives a round trip through India time', () {
      for (final instant in [
        DateTime.utc(2026, 11, 9, 18, 45, 30, 250),
        DateTime.utc(2026, 12, 31, 18, 30),
        DateTime.utc(2027, 2, 28, 23, 59, 59, 999),
        DateTime.utc(2026, 3, 29, 1, 30),
        DateTime.utc(2026, 11, 1, 6, 30),
      ]) {
        expect(IstClock.toInstant(IstClock.fromInstant(instant)), instant);
      }
    });

    test('wall converts only UTC-flagged values', () {
      expect(fields(IstClock.wall(DateTime.utc(2026, 11, 9, 4, 30))),
          [2026, 11, 9, 10, 0, 0, 0]);
      final plain = DateTime(2026, 11, 9, 10, 0);
      expect(identical(IstClock.wall(plain), plain), isTrue);
    });
  });

  group('parse / tryParse', () {
    test('text without a zone is already India time', () {
      expect(fields(IstClock.parse('2026-11-09T10:00:00')),
          [2026, 11, 9, 10, 0, 0, 0]);
      expect(fields(IstClock.parse('2026-11-09 10:00:00.250')),
          [2026, 11, 9, 10, 0, 0, 250]);
    });

    test('text with Z or an offset is converted to India time', () {
      expect(fields(IstClock.parse('2026-11-09T04:30:00Z')),
          [2026, 11, 9, 10, 0, 0, 0]);
      expect(fields(IstClock.parse('2026-11-09T10:00:00+05:30')),
          [2026, 11, 9, 10, 0, 0, 0]);
      expect(fields(IstClock.parse('2026-11-08T23:30:00-05:00')),
          [2026, 11, 9, 10, 0, 0, 0]);
    });

    test('a date alone is midnight India time of that date', () {
      expect(fields(IstClock.parse('2026-11-09')), [2026, 11, 9, 0, 0, 0, 0]);
    });

    test('the same moment written with and without a zone agrees', () {
      expect(IstClock.parse('2026-11-09T04:30:00Z'),
          IstClock.parse('2026-11-09T10:00:00'));
    });

    test('tryParse returns null for text that is not a date', () {
      expect(IstClock.tryParse('not a date'), isNull);
      expect(IstClock.tryParse(''), isNull);
      expect(IstClock.tryParse('null'), isNull);
      expect(IstClock.tryParse('2026-11-09T10:00:00'), isNotNull);
    });

    test('parse throws on bad text', () {
      expect(() => IstClock.parse('nope'), throwsFormatException);
    });
  });

  group('fromEpochMs', () {
    test('the Unix epoch is 05:30 on 1 Jan 1970 in India', () {
      expect(fields(IstClock.fromEpochMs(0)), [1970, 1, 1, 5, 30, 0, 0]);
    });

    test('a known instant converts exactly', () {
      final ms = DateTime.utc(2026, 11, 9, 18, 45).millisecondsSinceEpoch;
      expect(fields(IstClock.fromEpochMs(ms)), [2026, 11, 10, 0, 15, 0, 0]);
    });
  });

  test('the offset is India Standard Time, five hours thirty minutes', () {
    expect(IstClock.offset, const Duration(hours: 5, minutes: 30));
  });
}
