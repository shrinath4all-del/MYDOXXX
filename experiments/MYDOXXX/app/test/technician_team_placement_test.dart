import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/services/technician_duty_service.dart';
import 'package:mydox/services/technician_staffing_service.dart';

typedef Cp = TechnicianStaffingService;

void main() {
  Map<String, dynamic> applicant(String name,
          {int exp = 5, int noShows = 0, String at = '2026-10-24T10:00:00'}) =>
      {'name': name, 'experienceYears': exp, 'noShows': noShows, 'at': at, 'agencyId': ''};

  group('top 10 shortlist', () {
    final request = {
      'applicants': {
        for (var i = 0; i < 14; i++)
          'u$i': applicant('Dr $i', exp: i, at: '2026-10-24T10:${i.toString().padLeft(2, '0')}:00'),
        'late': applicant('Late', exp: 30, noShows: 2),
      },
      'allocatedUids': <String>[],
    };

    test('at most 10, fewest no-shows first, then most experience', () {
      final top = Cp.shortlist(request);
      expect(top.length, 10);
      expect(top.first.uid, 'u13'); // most experienced with no no-shows
      expect(top.map((e) => e.uid), isNot(contains('late')),
          reason: 'a physician with no-shows ranks below the rest');
      expect(top.last.uid, 'u4');
    });

    test('ties go to who applied first', () {
      final r = {
        'applicants': {
          'b': applicant('B', at: '2026-10-24T11:00:00'),
          'a': applicant('A', at: '2026-10-24T09:00:00'),
        },
        'allocatedUids': <String>[],
      };
      expect(Cp.shortlist(r).map((e) => e.uid), ['a', 'b']);
    });
  });

  group('application status in Applied', () {
    Map<String, dynamic> request(String status,
            {List<String> allocated = const [], Map<String, dynamic>? applicants}) =>
        {
          'status': status,
          'allocatedUids': allocated,
          'date': '2099-01-05',
          'start': '08:00',
          'end': '15:00',
          'applicants': applicants ?? {'me': applicant('Me')},
        };

    test('selected, shortlisted, applied', () {
      expect(Cp.applicationStatus(request('filled', allocated: ['me', 'a', 'b']), 'me'),
          'selected');
      expect(Cp.applicationStatus(request('open'), 'me'), 'shortlisted');
      final many = {
        for (var i = 0; i < 12; i++) 'u$i': applicant('D$i', exp: 20 - i),
        'me': applicant('Me', exp: 0),
      };
      expect(Cp.applicationStatus(request('open', applicants: many), 'me'), 'applied',
          reason: 'not in the best 10 yet');
    });

    test('not selected when the team was placed without him; closed when cancelled', () {
      expect(Cp.applicationStatus(request('filled', allocated: ['a', 'b', 'c']), 'me'),
          'not_selected');
      expect(Cp.applicationStatus(request('cancelled'), 'me'), 'closed');
    });
  });

  group('a placed physician\'s clashing locum shift', () {
    // week 1 from Monday 26 Oct 2026: a morning, b evening, c night
    final roster = CareDutyRoster(
        anchorMonday: DateTime.utc(2026, 10, 26), members: ['a', 'b', 'c']);

    Map<String, dynamic> shift(String id, String date, String start, String end,
            {String by = 'a', String status = 'claimed'}) =>
        {'id': id, 'date': date, 'start': start, 'end': end, 'status': status, 'claimedBy': by};

    test('the 27 October shift on his rotation time is released', () {
      // a works the morning (8 am to 3 pm) of 27 Oct
      final clash = shift('s27', '2026-10-27', '08:00', '14:00');
      final free = shift('s27e', '2026-10-27', '20:00', '23:00'); // after his duty
      final before = shift('s20', '2026-10-20', '08:00', '14:00'); // before the rotation
      final ids = TechnicianDutyService.clashingShiftIds(roster, 'a', [clash, free, before]);
      expect(ids, ['s27']);
    });

    test('a shift already started or someone else\'s is left alone', () {
      final started = shift('on', '2026-10-27', '08:00', '14:00', status: 'on_duty');
      final other = shift('o', '2026-10-27', '08:00', '14:00', by: 'b');
      expect(TechnicianDutyService.clashingShiftIds(roster, 'a', [started, other]), isEmpty);
    });
  });
}
