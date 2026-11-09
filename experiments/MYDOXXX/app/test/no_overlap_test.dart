import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/services/care_duty_service.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/utils/ist_clock.dart';

typedef Cp = CarePhysicianService;

/// A care physician can never hold two duties at the same time: a full-time
/// (rotation) duty, a hospital locum shift and a patient's home visit all
/// block one another.
void main() {
  fixedShiftTests();
  fullTimeClashTests();
  startDateTests();
  final now = DateTime(2099, 1, 1, 6, 0);

  Map<String, dynamic> shift(String id, String start, String end,
          {String status = 'claimed',
          String by = 'me',
          String postedBy = 'hospital',
          String type = 'ward',
          String date = '2099-01-05'}) =>
      {
        'id': id,
        'date': date,
        'start': start,
        'end': end,
        'status': status,
        'claimedBy': by,
        'postedBy': postedBy,
        'dutyType': type,
        'hospitalName': 'H',
        'procedures': <String>[],
      };

  final me = {'uid': 'me', 'isVerified': true, 'available': true};

  // week 1 from Monday 5 Jan 2099: 'me' works the Morning (8 am to 3 pm)
  final roster = CareDutyRoster(
      anchorMonday: DateTime.utc(2099, 1, 5), members: ['me', 'b', 'c']);
  final rosterBusy = [
    for (final d in roster.dutiesOf('me', DateTime.utc(2099, 1, 5), DateTime.utc(2099, 1, 11)))
      BusyInterval(d.start, d.end, 'Kush Hospital')
  ];

  group('full-time duty blocks a locum shift and a home visit', () {
    test('a locum over the morning rotation duty', () {
      final locum = shift('l', '10:00', '14:00');
      expect(Cp.rosterClashWith(locum, rosterBusy), contains('duty roster'));
    });

    test('a home visit over the morning rotation duty', () {
      final visit = shift('v', '10:00', '12:00', postedBy: 'patient', type: 'home');
      expect(Cp.rosterClashWith(visit, rosterBusy), isNotNull);
    });

    test('after the duty ends is free', () {
      final locum = shift('l', '16:00', '20:00');
      expect(Cp.rosterClashWith(locum, rosterBusy), isNull);
    });
  });

  group('a locum shift and a home visit block each other', () {
    test('a visit over a claimed locum', () {
      final locum = shift('l', '08:00', '14:00');
      final visit = shift('v', '10:00', '12:00',
          postedBy: 'patient', type: 'home', status: 'open', by: '');
      expect(Cp.claimBlockReason(visit, me, [locum], now),
          contains('already have a shift'));
    });

    test('a locum over a claimed visit', () {
      final visit = shift('v', '10:00', '12:00', postedBy: 'patient', type: 'home');
      final locum = shift('l', '08:00', '14:00', status: 'open', by: '');
      expect(Cp.claimBlockReason(locum, me, [visit], now),
          contains('already have a shift'));
    });

    test('two visits at the same time', () {
      final a = shift('a', '14:00', '16:00', postedBy: 'patient', type: 'home');
      final b = shift('b', '14:00', '16:00',
          postedBy: 'patient', type: 'home', status: 'open', by: '');
      expect(Cp.claimBlockReason(b, me, [a], now), isNotNull);
    });

    test('different hours on the same day are fine (2 to 4 AM and 2 to 8 PM)', () {
      final visit = shift('v', '02:00', '04:00', postedBy: 'patient', type: 'home');
      final locum = shift('l', '14:00', '20:00', status: 'open', by: '');
      expect(Cp.claimBlockReason(locum, me, [visit], now), isNull);
    });

    test('an overnight locum blocks a 2 to 4 AM visit next morning', () {
      final night = shift('n', '20:00', '08:00'); // 5 Jan 8 pm to 6 Jan 8 am
      final visit = shift('v', '02:00', '04:00',
          postedBy: 'patient', type: 'home', status: 'open', by: '', date: '2099-01-06');
      expect(Cp.claimBlockReason(visit, me, [night], now), isNotNull);
    });
  });

  group('placed in a full-time team: clashing duties are released', () {
    test('a locum shift and a home visit on the new rotation time', () {
      final locum = shift('l', '10:00', '14:00');
      final visit = shift('v', '09:00', '11:00', postedBy: 'patient', type: 'home');
      final free = shift('f', '16:00', '18:00');
      final ids = CareDutyService.clashingShiftIds(roster, 'me', [locum, visit, free]);
      expect(ids.toSet(), {'l', 'v'});
    });
  });

  test('a patient visit request is not offered to a physician who is busy then', () {
    final locum = [BusyInterval(
        IstClock.toInstant(
            Cp.shiftStart({'date': '2099-01-05', 'start': '08:00'})!),
        IstClock.toInstant(Cp.shiftEnd(
            {'date': '2099-01-05', 'start': '08:00', 'end': '14:00'})!))];
    final start = Cp.shiftStart({'date': '2099-01-05', 'start': '10:00'})!;
    expect(Cp.clashesWith(locum, start, start.add(const Duration(hours: 2))), isTrue);
  });
}

/// A one-shift placement: one physician, one fixed shift, every day.
void fixedShiftTests() {
  group('one-shift full-time placement', () {
    final r = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 1, 7),
        members: ['me', '', ''],
        fixed: DutyShift.evening);

    test('only the fixed shift exists, worked by him every day', () {
      final day = DateTime.utc(2099, 1, 20);
      expect(r.slotsOn(day).length, 1);
      expect(r.assigneeOf(r.slotsOn(day).single), 'me');
      expect(r.dutiesOf('me', DateTime.utc(2099, 1, 7), DateTime.utc(2099, 1, 13)).length, 7);
      expect(r.dutiesOf('other', DateTime.utc(2099, 1, 7), DateTime.utc(2099, 1, 13)), isEmpty);
    });

    test('it blocks a locum on the same hours but not on the morning', () {
      final busy = [
        for (final d in r.dutiesOf('me', DateTime.utc(2099, 1, 7), DateTime.utc(2099, 1, 9)))
          BusyInterval(d.start, d.end, 'H')
      ];
      Map<String, dynamic> s(String a, String b) => {
            'date': '2099-01-08', 'start': a, 'end': b, 'status': 'open'
          };
      expect(CarePhysicianService.rosterClashWith(s('16:00', '20:00'), busy), isNotNull);
      expect(CarePhysicianService.rosterClashWith(s('08:00', '12:00'), busy), isNull);
    });

    test('the team is read from a fixedShift record', () {
      final t = {'anchor': '2099-01-07', 'members': ['me'], 'fixedShift': 'night'};
      expect(CareDutyService.rosterOf(t).fixed, DutyShift.night);
      expect(CareDutyService.rosterOf({'anchor': '2099-01-07', 'members': ['a', 'b', 'c']}).fixed, isNull);
    });
  });
}

void fullTimeClashTests() {
  group('a full-time job cannot overlap a full-time duty', () {
    // he works the Evening (3 to 10 pm) every day at hospital X
    final r = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 1, 5),
        members: ['me', '', ''],
        fixed: DutyShift.evening);
    final busy = [
      for (final d in r.dutiesOf('me', DateTime.utc(2099, 1, 5), DateTime.utc(2099, 3, 30)))
        BusyInterval(d.start, d.end, 'X Hospital')
    ];
    Map<String, dynamic> req(String anchor, {String fixed = ''}) =>
        {'anchor': anchor, 'rotation': true, if (fixed.isNotEmpty) 'fixedShift': fixed};

    test('the same shift clashes', () {
      expect(CareDutyService.requestClash(req('2099-01-20', fixed: 'evening'), busy), 'X Hospital');
    });
    test('a different shift is fine', () {
      expect(CareDutyService.requestClash(req('2099-01-20', fixed: 'morning'), busy), isNull);
    });
    test('the night shift touches the evening end but does not overlap', () {
      expect(CareDutyService.requestClash(req('2099-01-20', fixed: 'night'), busy), isNull);
    });
    test('the three-shift team clashes (it includes his evening)', () {
      expect(CareDutyService.requestClash(req('2099-01-20'), busy), 'X Hospital');
    });
    test('free when he has no full-time duty', () {
      expect(CareDutyService.requestClash(req('2099-01-20'), const []), isNull);
    });
  });
}

void startDateTests() {
  test('nothing is rostered before the job start date', () {
    final r = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 11, 1), members: ['a', 'b', 'c']);
    expect(r.slotsOn(DateTime.utc(2099, 10, 31)), isEmpty);
    expect(r.dutiesOf('a', DateTime.utc(2099, 10, 1), DateTime.utc(2099, 10, 31)), isEmpty);
    expect(r.slotsOn(DateTime.utc(2099, 11, 1)).length, 3);
  });
}
