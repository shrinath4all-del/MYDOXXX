import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/config/test_lab_config.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/screens/care_physician/my_duties_view.dart';
import 'package:mydox/screens/nurse/nurse_my_duties_view.dart';
import 'package:mydox/screens/technician/technician_my_duties_view.dart';
import 'package:mydox/services/care_agency_service.dart';
import 'package:mydox/services/nurse_duty_service.dart';
import 'package:mydox/services/nurse_staffing_service.dart';
import 'package:mydox/services/technician_duty_service.dart';
import 'package:mydox/services/technician_staffing_service.dart';
import 'package:mydox/utils/ist_clock.dart';
import 'package:mydox/utils/ist_timestamp.dart';

/// "India time everywhere": the paths that used to read the DEVICE zone must give
/// the same answer whatever zone the machine is in. Every expectation below is a
/// fixed India time or a fixed UTC instant. Run this file with several
/// TZ=... values (UTC, Asia/Kolkata, America/New_York, Pacific/Auckland ...).
List<int> fields(DateTime t) =>
    [t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond];

void main() {
  tearDown(() => IstClock.debugSetInstantSource(null));

  group('Firestore timestamps', () {
    test('timestampOf stores an India wall-clock time as the right instant', () {
      expect(timestampOf(DateTime(2026, 10, 6, 9, 0)).toDate().toUtc(),
          DateTime.utc(2026, 10, 6, 3, 30));
    });

    test('timestampOf leaves a real instant alone', () {
      final instant = DateTime.utc(2026, 10, 6, 3, 30);
      expect(timestampOf(instant).toDate().toUtc(), instant);
    });

    test('a stored instant reads back as India time and as an instant', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 10, 6, 3, 30));
      expect(fields(ts.toIst()), [2026, 10, 6, 9, 0, 0, 0]);
      expect(ts.toInstant(), DateTime.utc(2026, 10, 6, 3, 30));
      expect(ts.toInstant().isUtc, isTrue);
    });

    test('write then read returns the same India time', () {
      final wall = DateTime(2026, 10, 6, 21, 45);
      expect(fields(timestampOf(wall).toIst()), fields(wall));
    });

    test('istTimeOf understands every stored form', () {
      expect(fields(istTimeOf(Timestamp.fromDate(DateTime.utc(2026, 10, 6, 3, 30)))!),
          [2026, 10, 6, 9, 0, 0, 0]);
      expect(fields(istTimeOf('2026-10-06T09:00:00')!), [2026, 10, 6, 9, 0, 0, 0]);
      expect(fields(istTimeOf('2026-10-06T03:30:00Z')!), [2026, 10, 6, 9, 0, 0, 0]);
      expect(fields(istTimeOf(DateTime.utc(2026, 10, 6, 3, 30))!),
          [2026, 10, 6, 9, 0, 0, 0]);
      expect(fields(istTimeOf(DateTime(2026, 10, 6, 9, 0))!),
          [2026, 10, 6, 9, 0, 0, 0]);
      expect(istTimeOf(null), isNull);
      expect(istTimeOf(''), isNull);
      expect(istTimeOf('not a date'), isNull);
    });

    test('the agency service reads stored shift times as India time', () {
      final ts = timestampOf(DateTime(2026, 10, 6, 9, 0));
      expect(fields(CareAgencyService.asTime(ts)!), [2026, 10, 6, 9, 0, 0, 0]);
      expect(fields(CareAgencyService.asTime('2026-10-06T09:00:00')!),
          [2026, 10, 6, 9, 0, 0, 0]);
    });
  });

  group('cloud session expiry uses the real instant', () {
    // The signed expiry is a real epoch time; India wall-clock time would be
    // 5.5 hours ahead of UTC and wrongly expire a valid session.
    final instant = DateTime.utc(2026, 11, 9, 12, 0);
    Map<String, dynamic> claims(int expiresMs) =>
        {'cloudLab': true, 'labOperatorUid': 'operator', 'labExpiresAt': expiresMs};

    test('valid for the next hour', () {
      IstClock.debugSetInstantSource(() => instant);
      expect(
          () => TestLabConfig.validateCloudClaims(
              claims(instant.add(const Duration(hours: 1)).millisecondsSinceEpoch)),
          returnsNormally);
    });

    test('rejected one second after it ends', () {
      IstClock.debugSetInstantSource(() => instant);
      expect(
          () => TestLabConfig.validateCloudClaims(claims(
              instant.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch)),
          throwsStateError);
    });

    test('rejected when it claims more than eight hours', () {
      IstClock.debugSetInstantSource(() => instant);
      expect(
          () => TestLabConfig.validateCloudClaims(claims(instant
              .add(const Duration(hours: 8, minutes: 6))
              .millisecondsSinceEpoch)),
          throwsStateError);
    });
  });

  group('roster clash for nurses and technicians', () {
    Map<String, dynamic> shift(String id, String start, String end) => {
          'id': id,
          'date': '2099-01-05',
          'start': start,
          'end': end,
          'status': 'claimed',
          'claimedBy': 'me',
        };
    // Monday 5 Jan 2099: 'me' works the Morning, 08:00-15:00 India time.
    final roster = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 1, 5), members: ['me', 'b', 'c']);
    final busy = [
      for (final d in roster.dutiesOf(
          'me', DateTime.utc(2099, 1, 5), DateTime.utc(2099, 1, 5)))
        BusyInterval(d.start, d.end, 'Kush Hospital')
    ];

    final checks = <String, String? Function(Map<String, dynamic>)>{
      'nurse': (s) => NurseStaffingService.rosterClashWith(s, busy),
      'technician': (s) => TechnicianStaffingService.rosterClashWith(s, busy),
    };
    checks.forEach((who, clash) {
      test('$who: a shift inside the duty clashes (10:00-14:00)', () {
        expect(clash(shift('x', '10:00', '14:00')), contains('duty roster'));
      });
      test('$who: before the duty is free (05:00-07:00)', () {
        expect(clash(shift('x', '05:00', '07:00')), isNull);
      });
      test('$who: starting when the duty ends is free (15:00-18:00)', () {
        expect(clash(shift('x', '15:00', '18:00')), isNull);
      });
    });

    final released = <String, List<String> Function(List<Map<String, dynamic>>)>{
      'nurse': (s) => NurseDutyService.clashingShiftIds(roster, 'me', s),
      'technician': (s) => TechnicianDutyService.clashingShiftIds(roster, 'me', s),
    };
    released.forEach((who, ids) {
      test('$who: only the overlapping claimed shift is released', () {
        expect(
            ids([
              shift('before', '05:00', '07:00'),
              shift('inside', '10:00', '14:00'),
              shift('after', '16:00', '20:00'),
            ]),
            ['inside']);
      });
    });
  });

  group('duty phase in India time', () {
    // Morning 08:00-15:00 India time on 5 Jan 2099 = 02:30-09:30 UTC.
    final slot = DutySlot(DateTime.utc(2099, 1, 5), DutyShift.morning);

    test('the slot is 02:30-09:30 UTC', () {
      expect(slot.start, DateTime.utc(2099, 1, 5, 2, 30));
      expect(slot.end, DateTime.utc(2099, 1, 5, 9, 30));
    });

    final cases = <String, List<DateTime>>{
      // now given as India wall-clock time
      'wall clock': [
        DateTime(2099, 1, 5, 7, 59),
        DateTime(2099, 1, 5, 8, 0),
        DateTime(2099, 1, 5, 14, 59),
        DateTime(2099, 1, 5, 15, 0),
      ],
      // the same four moments as real instants
      'real instant': [
        DateTime.utc(2099, 1, 5, 2, 29),
        DateTime.utc(2099, 1, 5, 2, 30),
        DateTime.utc(2099, 1, 5, 9, 29),
        DateTime.utc(2099, 1, 5, 9, 30),
      ],
    };
    cases.forEach((form, times) {
      test('care physician ($form): upcoming, ongoing, ongoing, completed', () {
        expect([for (final t in times) phaseOfSlot(slot, t)], [
          DutyPhase.upcoming,
          DutyPhase.ongoing,
          DutyPhase.ongoing,
          DutyPhase.completed
        ]);
      });
      test('nurse ($form): upcoming, ongoing, ongoing, completed', () {
        expect([for (final t in times) nursePhaseOfSlot(slot, t)], [
          NurseDutyPhase.upcoming,
          NurseDutyPhase.ongoing,
          NurseDutyPhase.ongoing,
          NurseDutyPhase.completed
        ]);
      });
      test('technician ($form): upcoming, ongoing, ongoing, completed', () {
        expect([for (final t in times) technicianPhaseOfSlot(slot, t)], [
          TechnicianDutyPhase.upcoming,
          TechnicianDutyPhase.ongoing,
          TechnicianDutyPhase.ongoing,
          TechnicianDutyPhase.completed
        ]);
      });
    });

    test('a claimed shift ends at its India end time', () {
      final s = {
        'status': 'claimed',
        'date': '2099-01-05',
        'start': '08:00',
        'end': '14:00'
      };
      expect(phaseOfShift(s, DateTime(2099, 1, 5, 13, 59)), DutyPhase.upcoming);
      expect(phaseOfShift(s, DateTime(2099, 1, 5, 14, 0)), DutyPhase.completed);
      expect(phaseOfShift(s, DateTime.utc(2099, 1, 5, 8, 29)), DutyPhase.upcoming);
      expect(phaseOfShift(s, DateTime.utc(2099, 1, 5, 8, 30)), DutyPhase.completed);
    });
  });

  group('taking over a duty', () {
    final roster = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 1, 5), members: ['me', 'b', 'c']);
    final slot = DutySlot(DateTime.utc(2099, 1, 5), DutyShift.morning);
    const started = 'That duty has already started.';

    test('allowed before the duty starts, refused from its start (wall clock)', () {
      expect(roster.checkTakeOver('b', slot, DateTime(2099, 1, 5, 7, 59)).problem,
          isNot(started));
      expect(roster.checkTakeOver('b', slot, DateTime(2099, 1, 5, 8, 0)).problem,
          started);
    });

    test('the same with real instants', () {
      expect(
          roster.checkTakeOver('b', slot, DateTime.utc(2099, 1, 5, 2, 29)).problem,
          isNot(started));
      expect(
          roster.checkTakeOver('b', slot, DateTime.utc(2099, 1, 5, 2, 30)).problem,
          started);
    });
  });
}
