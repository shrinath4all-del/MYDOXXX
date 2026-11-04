import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/nurse_duty_rate_service.dart';

void main() {
  group('care duty rates', () {
    test('2,000: physician 1,700, margin 300 = Sai 225 + MyDox 75', () {
      const r = NurseDutyRate(dutyType: 'icu', label: 'ICU duty', hospitalRate: 2000);
      expect(r.doctorPay, 1700);
      expect(r.margin, 300);
      expect(r.saiShare, 225);
      expect(r.mydoxShare, 75);
      expect(r.doctorPay + r.saiShare + r.mydoxShare, r.hospitalRate);
    });

    test('the three fixed prices', () {
      NurseDutyRate rate(int n) =>
          NurseDutyRate(dutyType: 'x', label: 'x', hospitalRate: n);
      expect(rate(1500).doctorPay, 1275); // ward
      expect(rate(1800).doctorPay, 1530); // specialty
      for (final n in [1500, 1800, 2000]) {
        final r = rate(n);
        expect(r.doctorPay + r.saiShare + r.mydoxShare, n,
            reason: 'every rupee is accounted for');
      }
    });

    test('shift fields: the hospital price and the physician pay', () {
      const r = NurseDutyRate(dutyType: 'ward', label: 'Ward', hospitalRate: 1500);
      final f = r.toShiftFields();
      expect(f['pay'], 1500);
      expect(f['doctorPay'], 1275);
      expect(f['rateSource'], 'master');
    });

    test('full-time team: monthly salary with the same margin and split', () {
      const r = NurseDutyRate(
          dutyType: 'icu', label: 'ICU', hospitalRate: 2000, monthlySalary: 55000);
      expect(r.monthlyMargin, 8250);
      expect(r.monthlyDoctorPay, 46750);
      expect(r.monthlySaiShare, 6188); // 75% of 8,250 (6,187.5 rounded)
      expect(r.monthlyMydoxShare, 2062);
      expect(r.monthlyDoctorPay + r.monthlySaiShare + r.monthlyMydoxShare, 55000);
      final f = r.toTeamFields();
      expect(f['pay'], 55000);
      expect(f['payPeriod'], 'month');
    });

    test('the three monthly salaries', () {
      NurseDutyRate m(int n) => NurseDutyRate(
          dutyType: 'x', label: 'x', hospitalRate: 1000, monthlySalary: n);
      expect(m(45000).monthlyDoctorPay, 38250);
      expect(m(50000).monthlyDoctorPay, 42500);
    });

    test('an inactive or priceless doc is not a rate', () {
      expect(NurseDutyRate.fromDoc('ward', {'hospitalRate': 1500, 'active': false}), isNull);
      expect(NurseDutyRate.fromDoc('ward', {'label': 'x'}), isNull);
      expect(NurseDutyRate.fromDoc('ward', {'hospitalRate': 1500})?.hospitalRate, 1500);
    });
  });
}
