import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/services/care_duty_service.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/utils/ist_clock.dart';

/// Shift dates and hours are typed as India wall-clock time, and duty rosters
/// are India instants. Clash checks must therefore give the same answer
/// whatever time zone the device (or the test machine) is set to.
///
/// Every expectation below is a fixed UTC instant or a fixed clash result, so
/// it holds under TZ=UTC and TZ=Asia/Kolkata alike. Before `wallToUtc`, the
/// shift hours were read in the device zone: on a UTC device a shift before
/// the Morning duty was reported as a clash and one inside it was missed.
void main() {
  Map<String, dynamic> shift(String id, String start, String end) => {
        'id': id,
        'date': '2099-01-05',
        'start': start,
        'end': end,
        'status': 'claimed',
        'claimedBy': 'me',
        'postedBy': 'hospital',
        'dutyType': 'ward',
        'hospitalName': 'H',
        'procedures': <String>[],
      };

  // Week 1 from Monday 5 Jan 2099: 'me' works the Morning, 8 am to 3 pm IST,
  // which is 02:30 to 09:30 UTC.
  final roster = CareDutyRoster(
      anchorMonday: DateTime.utc(2099, 1, 5), members: ['me', 'b', 'c']);
  final busy = [
    for (final d in roster.dutiesOf(
        'me', DateTime.utc(2099, 1, 5), DateTime.utc(2099, 1, 5)))
      BusyInterval(d.start, d.end, 'Kush Hospital')
  ];

  test('the Morning duty is 02:30 to 09:30 UTC', () {
    expect(busy, hasLength(1));
    expect(busy.single.start, DateTime.utc(2099, 1, 5, 2, 30));
    expect(busy.single.end, DateTime.utc(2099, 1, 5, 9, 30));
  });

  group('CareDutyClock.wallToUtc reads the fields as India time', () {
    test('10:00 IST is 04:30 UTC', () {
      expect(CareDutyClock.wallToUtc(DateTime(2099, 1, 5, 10, 0)),
          DateTime.utc(2099, 1, 5, 4, 30));
    });

    test('a UTC-flagged and a local value with the same fields agree', () {
      expect(CareDutyClock.wallToUtc(DateTime.utc(2099, 1, 5, 10, 0)),
          CareDutyClock.wallToUtc(DateTime(2099, 1, 5, 10, 0)));
    });

    test('00:15 IST belongs to the previous UTC day', () {
      expect(CareDutyClock.wallToUtc(DateTime(2099, 1, 6, 0, 15)),
          DateTime.utc(2099, 1, 5, 18, 45));
    });
  });

  group('CareDutyClock.today', () {
    test('a plain India wall-clock time is not converted a second time', () {
      expect(CareDutyClock.today(DateTime(2026, 11, 9, 23, 59)),
          DateTime.utc(2026, 11, 9));
      expect(CareDutyClock.today(DateTime(2026, 11, 10, 0, 15)),
          DateTime.utc(2026, 11, 10));
    });

    test('a UTC-flagged instant is converted to the India day', () {
      expect(CareDutyClock.today(DateTime.utc(2026, 11, 9, 18, 29)),
          DateTime.utc(2026, 11, 9));
      expect(CareDutyClock.today(DateTime.utc(2026, 11, 9, 18, 30)),
          DateTime.utc(2026, 11, 10));
    });

    test('IstClock.now() gives the India day whatever the machine zone', () {
      IstClock.debugSetInstantSource(() => DateTime.utc(2026, 11, 9, 18, 45));
      addTearDown(() => IstClock.debugSetInstantSource(null));
      expect(CareDutyClock.today(IstClock.now()), DateTime.utc(2026, 11, 10));
    });
  });

  group('rosterClashWith', () {
    test('a locum inside the Morning duty clashes (10:00-14:00 IST)', () {
      expect(CarePhysicianService.rosterClashWith(shift('l', '10:00', '14:00'), busy),
          contains('duty roster'));
    });

    test('a shift before the duty is free (05:00-07:00 IST)', () {
      expect(CarePhysicianService.rosterClashWith(shift('l', '05:00', '07:00'), busy),
          isNull);
    });

    test('a shift that ends at the duty start is free (06:00-08:00 IST)', () {
      expect(CarePhysicianService.rosterClashWith(shift('l', '06:00', '08:00'), busy),
          isNull);
    });

    test('a shift that starts at the duty end is free (15:00-18:00 IST)', () {
      expect(CarePhysicianService.rosterClashWith(shift('l', '15:00', '18:00'), busy),
          isNull);
    });

    test('a shift crossing the duty start clashes (07:00-09:00 IST)', () {
      expect(CarePhysicianService.rosterClashWith(shift('l', '07:00', '09:00'), busy),
          isNotNull);
    });
  });

  group('clashingShiftIds', () {
    test('only the shift that overlaps the rostered duty is released', () {
      final ids = CareDutyService.clashingShiftIds(roster, 'me', [
        shift('before', '05:00', '07:00'),
        shift('inside', '10:00', '14:00'),
        shift('after', '16:00', '20:00'),
      ]);
      expect(ids, ['inside']);
    });
  });
}
