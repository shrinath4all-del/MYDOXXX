import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/care_duty_roster.dart';

void main() {
  // Monday 5 Oct 2026 is week 1; A, B, C
  final roster = CareDutyRoster(
      anchorMonday: DateTime.utc(2026, 10, 5), members: ['a', 'b', 'c']);
  DutySlot slot(String date, DutyShift s) =>
      DutySlot(DutySlot.parseDate(date)!, s);

  group('weekly rotation', () {
    test('matches the approved 3-week table', () {
      String who(int week, DutyShift s) => roster.plannedFor(DutySlot(
          DateTime.utc(2026, 10, 5).add(Duration(days: 7 * week)), s));
      expect([for (var w = 0; w < 4; w++) who(w, DutyShift.morning)],
          ['a', 'b', 'c', 'a']);
      expect([for (var w = 0; w < 4; w++) who(w, DutyShift.evening)],
          ['b', 'c', 'a', 'b']);
      expect([for (var w = 0; w < 4; w++) who(w, DutyShift.night)],
          ['c', 'a', 'b', 'c']);
    });

    test('the shift stays fixed from Monday to Sunday', () {
      for (var d = 0; d < 7; d++) {
        final day = DateTime.utc(2026, 10, 5 + d);
        expect(roster.plannedFor(DutySlot(day, DutyShift.morning)), 'a');
      }
      expect(roster.plannedFor(slot('2026-10-12', DutyShift.morning)), 'b');
    });

    test('each physician cycles Morning, Night, Evening', () {
      String shiftOf(String uid, int week) => [
            for (final s in DutyShift.values)
              if (roster.plannedFor(DutySlot(
                      DateTime.utc(2026, 10, 5).add(Duration(days: 7 * week)),
                      s)) ==
                  uid)
                s.key
          ].single;
      expect([for (var w = 0; w < 3; w++) shiftOf('a', w)],
          ['morning', 'night', 'evening']);
    });

    test('hours: morning 7, evening 7, night 10 (ends next day 08:00)', () {
      final night = slot('2026-12-31', DutyShift.night);
      expect(night.end.difference(night.start).inHours, 10);
      expect(CareDutyClock.utcToIst(night.end).day, 1);
      expect(CareDutyClock.utcToIst(night.end).year, 2027);
      expect(CareDutyClock.utcToIst(night.end).hour, 8);
    });

    test('a three-week cycle gives everyone 168 scheduled hours', () {
      for (final uid in ['a', 'b', 'c']) {
        final total = roster
            .dutiesOf(uid, DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 25))
            .fold<int>(0, (t, s) => t + s.shift.hours);
        expect(total, 168);
      }
    });
  });

  group('validation', () {
    final now = DateTime.utc(2026, 10, 6, 0, 0);

    test('a started duty cannot be changed', () {
      final started = slot('2026-10-05', DutyShift.morning);
      expect(roster.checkTakeOver('r', started, now).ok, isFalse);
    });

    test('relief can take a free future duty', () {
      final duty = slot('2026-10-08', DutyShift.night); // c's week-1 night
      expect(roster.assigneeOf(duty), 'c');
      expect(roster.checkTakeOver('r', duty, now).ok, isTrue);
    });

    test('relief with an overlapping booking is rejected', () {
      final duty = slot('2026-10-08', DutyShift.night);
      final busy = [
        BusyInterval(duty.start.add(const Duration(hours: 1)),
            duty.end.subtract(const Duration(hours: 1)))
      ];
      expect(roster.checkTakeOver('r', duty, now, others: busy).ok, isFalse);
    });

    test('Sunday night cannot be followed by Monday morning', () {
      // c works the night of Sunday 11 Oct; a works morning of Monday 12 Oct? no, b does.
      // Swap so c would work Monday 12 morning too: c takes b's Monday morning.
      final sunNight = slot('2026-10-11', DutyShift.night);
      final monMorning = slot('2026-10-12', DutyShift.morning);
      expect(roster.assigneeOf(sunNight), 'c');
      expect(roster.assigneeOf(monMorning), 'b');
      final r = roster.checkTakeOver('c', monMorning, now);
      expect(r.ok, isFalse);
      expect(r.problem, contains('last night of a week'));
    });

    test('Monday evening after Sunday night is allowed', () {
      final monEvening = slot('2026-10-12', DutyShift.evening);
      expect(roster.assigneeOf(monEvening), 'c'); // week 2 evening is c
      expect(roster.checkTakeOver('c', monEvening, now).ok, isTrue);
    });

    test('swap exchanges both and checks both', () {
      final mine = slot('2026-10-07', DutyShift.morning); // a
      final theirs = slot('2026-10-07', DutyShift.evening); // b
      expect(roster.checkSwap('a', mine, 'b', theirs, now).ok, isTrue);
      expect(roster.checkSwap('a', mine, 'a', theirs, now).ok, isFalse);
      expect(roster.checkSwap('a', mine, 'b', mine, now).ok, isFalse);
      // stale: the duties are not held by those two any more
      expect(roster.checkSwap('b', mine, 'a', theirs, now).ok, isFalse);
    });

    test('a swap that makes three duties in a row is rejected', () {
      // b: evening (15-22) on Wed 7; swapping b into Wed morning (08-15) and
      // keeping evening 15-22 makes two touching duties; add the night too.
      final withOverrides = CareDutyRoster(
        anchorMonday: DateTime.utc(2026, 10, 5),
        members: ['a', 'b', 'c'],
        overrides: {
          '2026-10-07|evening': 'a', // a: morning + evening touching
        },
      );
      final night = slot('2026-10-07', DutyShift.night); // c's
      final r = withOverrides.checkTakeOver('a', night, now);
      expect(r.ok, isFalse);
      expect(r.problem, contains('three duties'));
    });
  });
}
