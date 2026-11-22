import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_duty_rate_service.dart';

void main() {
  const base = CareDutyRate(
    dutyType: 'icu',
    label: 'ICU duty',
    hospitalRate: 2000,
    monthlySalary: 55000,
  );

  test('the three categories price every duty as agreed', () {
    const want = {
      // the pediatric (specialty) duty costs the same as ICU; casualty has the
      // old specialty prices
      'small': {'icu': 1500, 'ward': 1100, 'casualty': 1200, 'specialty': 1500},
      'medium': {
        'icu': 2000,
        'ward': 1500,
        'casualty': 1800,
        'specialty': 2000,
      },
      'high': {'icu': 2500, 'ward': 1700, 'casualty': 2000, 'specialty': 2500},
    };
    for (final c in want.entries) {
      for (final d in c.value.entries) {
        expect(
          HospitalCategory.rateFor(c.key, d.key),
          d.value,
          reason: '${c.key} ${d.key}',
        );
      }
    }
  });

  test('a duty is priced by the hospital category, keeping the 15 % split', () {
    final small = base.forCategory('small');
    expect(small.hospitalRate, 1500);
    expect(small.doctorPay, 1275); // 1500 - 15 %
    expect(small.saiShare + small.mydoxShare, small.margin);
    expect(base.forCategory('high').hospitalRate, 2500);
    expect(small.monthlySalary, 55000); // the salary is not category priced
  });

  test('an unknown or missing category is medium', () {
    expect(HospitalCategory.normalize(null), 'medium');
    expect(HospitalCategory.normalize('gold'), 'medium');
    expect(base.forCategory(null).hospitalRate, 2000);
  });

  test('the master table can override a category price', () {
    final r = base.forCategory('small', {
      'categoryRates': {'small': 1600},
    });
    expect(r.hospitalRate, 1600);
  });

  test(
    'streamed quote retains overrides and matches submission including mapped duties',
    () {
      final documents = <String, Map<String, dynamic>>{
        'icu': {
          'hospitalRate': 2000,
          'monthlySalary': 55000,
          'categoryRates': {'small': 1600},
        },
        'specialty': {
          'hospitalRate': 1800,
          'monthlySalary': 49000,
          'categoryRates': {'small': 1300},
        },
      };
      final streamed = CareDutyRates.fromMasterDocuments(documents);
      for (final entry in {
        'icu': 1600,
        'specialty': 1600,
        'casualty': 1300,
      }.entries) {
        final quote = streamed[entry.key]!.forCategory('small');
        final submitted = CareDutyRates.fromMasterDocument(
          entry.key,
          documents[CareDutyRates.sourceDoc[entry.key] ?? entry.key],
          category: 'small',
        )!;
        expect(quote.hospitalRate, entry.value);
        expect(quote.toShiftFields(), submitted.toShiftFields());
        expect(quote.toTeamFields(), submitted.toTeamFields());
      }
      expect(streamed['specialty']!.monthlySalary, 55000);
      expect(streamed['casualty']!.monthlySalary, 49000);
    },
  );

  test(
    'missing rates use category defaults but disabled or invalid masters stay unavailable',
    () {
      expect(
        CareDutyRates.fromMasterDocuments(
          {},
        )['icu']!
            .forCategory('small')
            .hospitalRate,
        1500,
      );
      expect(
        CareDutyRates.fromMasterDocument(
          'icu',
          null,
          category: 'small',
        )!
            .hospitalRate,
        1500,
      );
      for (final document in [
        <String, dynamic>{'hospitalRate': 2000, 'active': false},
        <String, dynamic>{'hospitalRate': 0},
      ]) {
        expect(
          CareDutyRates.fromMasterDocuments({
            'icu': document,
          }).containsKey('icu'),
          isFalse,
        );
        expect(
          CareDutyRates.fromMasterDocument('icu', document, category: 'small'),
          isNull,
        );
      }
    },
  );

  test('malformed overrides do not change the agreed category rate', () {
    for (final override in [0, 0.4, -1, '1600', double.infinity, double.nan, null]) {
      final document = <String, dynamic>{
        'hospitalRate': 2000,
        'categoryRates': {'small': override},
      };
      expect(
        CareDutyRates.fromMasterDocument(
          'icu',
          document,
          category: 'small',
        )!
            .hospitalRate,
        1500,
      );
    }
  });

  test('unusable monetary and split configuration never creates zero or negative pay', () {
    for (final document in [
      <String, dynamic>{'hospitalRate': 0.4},
      <String, dynamic>{'hospitalRate': double.infinity},
      <String, dynamic>{'hospitalRate': 2000, 'platformMarginPct': 101},
      <String, dynamic>{'hospitalRate': 2000, 'saiSharePct': 0, 'mydoxSharePct': 0},
    ]) {
      expect(CareDutyRates.fromMasterDocument('icu', document, category: 'small'), isNull);
      expect(CareDutyRates.fromMasterDocuments({'icu': document}).containsKey('icu'), isFalse);
    }
    for (final salary in [0.4, double.infinity, double.nan, -1, '55000']) {
      final rate = CareDutyRates.fromMasterDocument('icu', {
        'hospitalRate': 2000,
        'monthlySalary': salary,
      }, category: 'small')!;
      expect(rate.monthlySalary, isNull);
      expect(rate.hospitalRate, 1500);
    }
  });
}
