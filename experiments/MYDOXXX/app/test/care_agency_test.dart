import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_agency_service.dart';
import 'package:mydox/utils/ist_timestamp.dart';

void main() {
  // Tuesday 6 Oct 2026, 10:00
  final now = DateTime(2026, 10, 6, 10, 0);
  final today = '2026-10-06';
  Timestamp at(int h, int m, {int day = 6}) =>
      timestampOf(DateTime(2026, 10, day, h, m));

  Map<String, dynamic> duty(String doctorId,
          {String type = 'locum',
          String status = 'scheduled',
          int startH = 8,
          Timestamp? checkIn,
          Timestamp? checkOut,
          num rate = 3200,
          String date = '2026-10-06',
          String payout = 'due'}) {
    final shares = CareAgencyService.split(rate, const {});
    return {
      'doctorId': doctorId,
      'type': type,
      'status': status,
      'date': date,
      'shiftStart': at(startH, 0),
      'shiftEnd': at(startH + 8, 0),
      if (checkIn != null) 'checkInAt': checkIn,
      if (checkOut != null) 'checkOutAt': checkOut,
      'hospitalRate': rate,
      'doctorPay': shares.doctorPay,
      'agencyShare': shares.agencyShare,
      'appShare': shares.appShare,
      'payoutStatus': payout,
    };
  }

  group('money split', () {
    test('₹3,200 ICU locum: doctor 2,560 · agency 480 · app 160', () {
      final s = CareAgencyService.split(3200, {
        'splitDoctorPct': 80,
        'splitAgencyPct': 15,
        'splitAppPct': 5,
      });
      expect([s.doctorPay, s.agencyShare, s.appShare], [2560, 480, 160]);
    });

    test('app share absorbs rounding', () {
      final s = CareAgencyService.split(2799, const {});
      expect(s.doctorPay + s.agencyShare + s.appShare, 2799);
    });

    test('agency percentages are used', () {
      final s = CareAgencyService.split(1000,
          {'splitDoctorPct': 70, 'splitAgencyPct': 20, 'splitAppPct': 10});
      expect([s.doctorPay, s.agencyShare, s.appShare], [700, 200, 100]);
    });
  });

  group('duty status', () {
    test('late after start + 15 min with no check-in', () {
      final d = duty('a', startH: 9); // 09:00, now 10:00
      expect(CareAgencyService.dutyState(d, now), 'late');
      expect(CareAgencyService.lateMinutes(d, now), 60);
      expect(
          CareAgencyService.dutyState(
              d, DateTime(2026, 10, 6, 9, 10)), 'scheduled');
    });

    test('check-in 25 min late shows "Late 25m"', () {
      final d = duty('a', startH: 8, checkIn: at(8, 25));
      expect(CareAgencyService.dutyState(d, now), 'on_duty');
      expect(CareAgencyService.lateMinutes(d, now), 25);
      final onTime = duty('b', startH: 8, checkIn: at(8, 10));
      expect(CareAgencyService.lateMinutes(onTime, now), 0);
    });

    test('absent 4 h after start with no check-in', () {
      final d = duty('a', startH: 5); // 05:00, now 10:00
      expect(CareAgencyService.shouldAutoAbsent(d, now), isTrue);
      expect(CareAgencyService.shouldAutoAbsent(duty('b', startH: 7), now),
          isFalse);
      expect(
          CareAgencyService.shouldAutoAbsent(
              duty('c', startH: 5, checkIn: at(5, 30)), now),
          isFalse);
    });

    test('night shift ends the next morning', () {
      final t = CareAgencyService.shiftTimes(DateTime(2026, 10, 6), '20:00', '08:00');
      expect(t.start, DateTime(2026, 10, 6, 20));
      expect(t.end, DateTime(2026, 10, 7, 8));
    });

    test('check-in opens 1 h before the shift', () {
      final d = duty('a', startH: 11);
      expect(CareAgencyService.canCheckIn(d, now), isTrue); // 10:00
      expect(CareAgencyService.canCheckIn(d, DateTime(2026, 10, 6, 9, 30)),
          isFalse);
      expect(CareAgencyService.canCheckOut(d), isFalse);
      expect(CareAgencyService.canCheckOut({...d, 'checkInAt': at(10, 50)}),
          isTrue);
    });
  });

  group('control room numbers', () {
    final doctors = [
      {'id': 'perm1', 'placementType': 'permanent', 'active': true},
      {'id': 'locum1', 'placementType': 'pool', 'active': true},
      {'id': 'locum2', 'placementType': 'pool', 'active': true},
      {'id': 'emer1', 'placementType': 'pool', 'active': true},
      {'id': 'nojob1', 'placementType': 'pool', 'active': true},
      {
        'id': 'leave1',
        'placementType': 'pool',
        'active': true,
        'leaveFrom': '2026-10-05',
        'leaveTo': '2026-10-08'
      },
      {'id': 'gone', 'placementType': 'pool', 'active': false},
    ];
    final duties = [
      duty('perm1', type: 'permanent', startH: 9, checkIn: at(8, 51)),
      duty('locum1', startH: 5), // absent by status below
      duty('locum2', startH: 8, checkIn: at(8, 25), checkOut: at(9, 55)),
      duty('emer1', type: 'emergency', startH: 9), // late, not checked in
      duty('nojob1', status: 'cancelled'),
      // earlier this month, already paid
      duty('locum1', date: '2026-10-02', payout: 'paid', rate: 2800,
          checkIn: at(8, 0, day: 2), checkOut: at(16, 0, day: 2)),
    ];
    duties[1]['status'] = 'absent';

    final todayOnly = duties.where((d) => d['date'] == today).toList();

    test('doctor pool and attendance (today)', () {
      final s = CareAgencyService.summarize(
          doctors: doctors, periodDuties: todayOnly, now: now);
      expect(s.totalDoctors, 6); // inactive not counted
      expect(s.permanentPlaced, 1);
      expect(s.locumSent, 2); // locum1 (absent) + locum2
      expect(s.emergencyLocum, 1);
      expect(s.onDutyNow, 1); // perm1
      expect(s.absent, 1);
      expect(s.completed, 1);
      expect(s.late, 2); // emer1 not checked in + locum2 checked in 25m late
      expect(s.onLeave, 1);
      expect(s.noJobToday, 1); // nojob1 (its duty was cancelled)
    });

    test('money excludes absent and cancelled duties', () {
      final s = CareAgencyService.summarize(
          doctors: doctors, periodDuties: todayOnly, now: now);
      // perm1 + locum2 + emer1 = 3 × 3,200
      expect(s.billed, 9600);
      expect(s.doctorPayouts, 3 * 2560);
      expect(s.agencyShare, 3 * 480);
      expect(s.appShare, 3 * 160);
      expect(s.billed, s.doctorPayouts + s.agencyShare + s.appShare);
    });

    test('month: paid and due split', () {
      final s = CareAgencyService.summarize(
          doctors: doctors, periodDuties: duties, now: now);
      expect(s.billed, 9600 + 2800);
      expect(s.doctorPaid, 2240); // 80% of 2,800
      expect(s.doctorDue, 3 * 2560);
    });
  });

  test('period ranges', () {
    expect(CareAgencyService.periodRange('today', now),
        (from: today, to: today));
    expect(CareAgencyService.periodRange('week', now),
        (from: '2026-10-05', to: '2026-10-11')); // Mon–Sun
    expect(CareAgencyService.periodRange('month', now),
        (from: '2026-10-01', to: '2026-10-31'));
  });

  test('phone numbers match however they are typed', () {
    expect(CareAgencyService.normalizePhone('+91 98765 43210'), '9876543210');
    expect(CareAgencyService.normalizePhone('098765-43210'), '9876543210');
  });
}
