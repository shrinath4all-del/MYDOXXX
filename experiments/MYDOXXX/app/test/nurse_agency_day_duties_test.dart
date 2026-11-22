import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/nurse_agency_day_duties.dart';

void main() {
  leaveTests();
  final day = DateTime(2099, 1, 12);

  Map<String, dynamic> shift(String id, String type, String slot, String by,
          {String status = 'claimed', String date = '2099-01-12'}) =>
      {
        'id': id,
        'date': date,
        'dutyType': type,
        'slot': slot,
        'status': status,
        'claimedBy': by,
        'claimedByName': 'Dr $by',
        'hospitalName': 'H $id',
      };

  final shifts = [
    shift('1', 'icu', 'morning', 'a'),
    shift('2', 'icu', 'evening', 'b'),
    shift('3', 'ward', 'night', 'c', status: 'completed'),
    shift('4', 'casualty', 'morning', 'a', date: '2099-01-13'), // other day
    shift('5', 'ward', 'morning', 'd', status: 'open'), // nobody yet
    shift('6', 'specialty', 'morning', 'e', status: 'cancelled'),
  ];

  // a full-time team from 5 Jan: a morning, b evening, c night in week 1
  final teams = [
    {
      'id': 't',
      'status': 'active',
      'hospitalName': 'Team Hospital',
      'anchor': '2099-01-05',
      'members': ['x', 'y', 'z'],
      'memberNames': ['X', 'Y', 'Z'],
    }
  ];

  test('locum duties of the day: taken shifts only', () {
    final l = NurseAgencyDayDuties.locums(shifts, day);
    expect(l.map((d) => d.uid), ['a', 'b', 'c']);
    expect(l.where((d) => d.dutyType == 'icu').length, 2);
    // the evening locum slot is the Afternoon card
    expect(l.firstWhere((d) => d.uid == 'b').part, 'afternoon');
  });

  test('full-time duties of the day: the three shifts of the rotation', () {
    final f = NurseAgencyDayDuties.fullTime(teams, day);
    expect(f.length, 3);
    expect(f.map((d) => d.part).toSet(), {'morning', 'afternoon', 'night'});
    expect(f.every((d) => d.hospital == 'Team Hospital'), isTrue);
  });

  test('no full-time duty before the team starts', () {
    expect(NurseAgencyDayDuties.fullTime(teams, DateTime(2099, 1, 4)), isEmpty);
  });

  test('active people counts each physician once', () {
    final all = NurseAgencyDayDuties.all([...shifts, shift('7', 'ward', 'night', 'a')], teams, day);
    expect(NurseAgencyDayDuties.people(all), 6); // a, b, c + x, y, z
  });
}

void leaveTests() {
  Map<String, dynamic> leave(String uid, String key, String status, {String by = ''}) => {
        'type': 'leave',
        'requesterUid': uid,
        'requesterName': 'Dr $uid',
        'hospitalName': 'H',
        'sourceKey': key,
        'status': status,
        if (by.isNotEmpty) 'acceptedByName': by,
      };

  test('nurses on leave on a day: approved leave only', () {
    final reqs = [
      leave('a', '2099-01-12|morning', 'pending'), // approved, finding a relief
      leave('b', '2099-01-12|night', 'accepted', by: 'Dr R'), // covered
      leave('c', '2099-01-12|evening', 'awaiting_hospital'), // not yet leave
      leave('d', '2099-01-12|morning', 'declined'),
      leave('e', '2099-01-12|morning', 'withdrawn'),
      leave('f', '2099-01-13|morning', 'accepted'), // another day
    ];
    final l = NurseAgencyDayDuties.leaves(reqs, DateTime(2099, 1, 12));
    expect(l.map((x) => x.uid), ['a', 'b']);
    expect(l.firstWhere((x) => x.uid == 'b').coveredBy, 'Dr R');
    expect(l.firstWhere((x) => x.uid == 'a').coveredBy, '');
  });
}
