import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_earnings.dart';

void main() {
  Map<String, dynamic> duty(String date, String status,
          {int mydox = 75, int sai = 225, String? type, String name = 'Dr A'}) =>
      {
        'date': date,
        'status': status,
        'appShare': mydox,
        'agencyShare': sai,
        'doctorName': name,
        if (type != null) 'dutyType': type,
      };

  final now = DateTime.utc(2026, 10, 23, 6, 0); // 11:30 in India, same date
  final duties = [
    duty('2026-10-23', 'completed'),
    duty('2026-10-23', 'completed', mydox: 56, sai: 169),
    duty('2026-10-23', 'on_duty'), // not finished: not earned yet
    duty('2026-10-05', 'completed'),
    duty('2026-03-02', 'completed'),
    duty('2025-12-31', 'completed'),
    duty('2026-10-23', 'absent'),
  ];

  group('earnings', () {
    test('admin sees MyDox\'s 25%, the agency its 75%', () {
      expect(CareEarnings.today(duties, CareEarnings.mydox, now), 75 + 56);
      expect(CareEarnings.today(duties, CareEarnings.sai, now), 225 + 169);
    });

    test('month and year totals count completed duties only', () {
      expect(CareEarnings.thisMonth(duties, CareEarnings.mydox, now), 75 + 56 + 75);
      expect(CareEarnings.thisYear(duties, CareEarnings.mydox, now), 75 + 56 + 75 + 75);
    });

    test('any particular date', () {
      expect(CareEarnings.total(duties, CareEarnings.mydox, '2026-10-05'), 75);
      expect(CareEarnings.total(duties, CareEarnings.mydox, '2025-12-31'), 75);
      expect(CareEarnings.total(duties, CareEarnings.mydox, '2026-01-01'), 0);
    });

    test('who worked on a date: checked in or completed', () {
      final worked = CareEarnings.workedOn(duties, '2026-10-23');
      expect(worked.length, 3); // two completed + one on duty, not the no-show
    });

    test('duty type label, also for duties made before it was saved', () {
      expect(CareEarnings.dutyTypeLabel({'dutyType': 'specialty'}), 'Specialty duty');
      expect(CareEarnings.dutyTypeLabel({'dutyType': 'icu'}), 'ICU duty');
      expect(CareEarnings.dutyTypeLabel({'unit': 'icu'}), 'ICU duty');
      expect(CareEarnings.dutyTypeLabel({'unit': 'night'}), 'Ward duty');
    });
  });
}
