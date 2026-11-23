import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/utils/ist_clock.dart';

void main() {
  // a full-time job posted this evening for today (shift time 08:00 already past)
  final today = IstClock.now();
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final job = {
    'isTeam': true,
    'rotation': true,
    'status': 'open',
    'date': key(today),
    'start': '00:00',
    'end': '08:00',
    'teamSize': 3,
    'dutyType': 'ward',
    'area': 'Kothrud',
  };
  final me = {
    'uid': 'cp1',
    'dutyTypes': ['ward'],
    'areas': ['Kothrud'],
  };

  test('a full-time job for today stays open all day', () {
    expect(CarePhysicianService.shiftFits(job, me, IstClock.now()), isTrue);
    expect(CarePhysicianService.applicationStatus(
        {...job, 'applicantUids': ['cp1']}, 'cp1'), 'applied');
  });

  test('it closes once its start day is over', () {
    final yesterday = {...job, 'date': key(today.subtract(const Duration(days: 1)))};
    expect(CarePhysicianService.shiftFits(yesterday, me, IstClock.now()), isFalse);
    expect(CarePhysicianService.applicationStatus(yesterday, 'cp1'), 'closed');
  });

  test('a single shift still closes when it starts', () {
    final shift = {...job, 'rotation': false, 'isTeam': false, 'start': '00:00'};
    expect(CarePhysicianService.shiftFits(shift, me, IstClock.now()), isFalse);
  });
}
