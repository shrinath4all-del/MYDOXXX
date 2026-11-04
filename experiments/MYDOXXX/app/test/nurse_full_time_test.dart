import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/services/nurse_duty_service.dart';

/// Full-time nurse jobs: one fixed shift or all three, never overlapping,
/// and nothing rostered before the start date.
void main() {
  final fixed = CareDutyRoster(
      anchorMonday: DateTime.utc(2099, 1, 7),
      members: ['me', '', ''],
      fixed: DutyShift.evening);
  final busy = [
    for (final d in fixed.dutiesOf('me', DateTime.utc(2099, 1, 7), DateTime.utc(2099, 3, 30)))
      BusyInterval(d.start, d.end, 'X Hospital')
  ];
  Map<String, dynamic> req(String anchor, {String shift = ''}) =>
      {'anchor': anchor, 'rotation': true, if (shift.isNotEmpty) 'fixedShift': shift};

  test('one fixed shift is worked every day', () {
    expect(fixed.slotsOn(DateTime.utc(2099, 1, 20)).length, 1);
    expect(fixed.dutiesOf('me', DateTime.utc(2099, 1, 7), DateTime.utc(2099, 1, 13)).length, 7);
  });

  test('the team record says which shift is fixed', () {
    expect(NurseDutyService.rosterOf({'anchor': '2099-01-07', 'members': ['me'], 'fixedShift': 'night'}).fixed,
        DutyShift.night);
  });

  test('a full-time job cannot overlap a full-time duty', () {
    expect(NurseDutyService.requestClash(req('2099-01-20', shift: 'evening'), busy), 'X Hospital');
    expect(NurseDutyService.requestClash(req('2099-01-20'), busy), 'X Hospital');
    expect(NurseDutyService.requestClash(req('2099-01-20', shift: 'morning'), busy), isNull);
    expect(NurseDutyService.requestClash(req('2099-01-20', shift: 'night'), busy), isNull);
  });

  test('nothing is rostered before the start date', () {
    final r = CareDutyRoster(
        anchorMonday: DateTime.utc(2099, 11, 1), members: ['a', 'b', 'c']);
    expect(r.slotsOn(DateTime.utc(2099, 10, 31)), isEmpty);
    expect(r.slotsOn(DateTime.utc(2099, 11, 1)).length, 3);
  });
}
