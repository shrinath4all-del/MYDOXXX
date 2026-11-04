import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/pricing_service.dart';

void main() {
  test('prices come only from Firestore: nothing set means nothing to charge',
      () {
    const empty = PricingSettings();
    expect(empty.urgentSurcharge(500), isNull);
    expect(empty.nurseFee(3), isNull);
    expect(empty.doctorHomeVisitExtra, isNull);
    expect(empty.sosEmergencyFee, isNull);
  });

  test('same rules as the server', () {
    final p = PricingSettings.fromMap({
      'urgentSurchargePct': 20,
      'doctorHomeVisitExtra': 100,
      'nurseDailyRate': 1000,
      'sosEmergencyFee': 1200,
    });
    expect(p.urgentSurcharge(520), 104);
    expect(p.urgentSurcharge(700), 140);
    expect(p.nurseFee(5), 5000);
    expect(p.nurseFee(0), 1000, reason: 'at least one day');
    expect(p.doctorHomeVisitExtra, 100);
    expect(p.sosEmergencyFee, 1200);
  });

  test('bad values are treated as not set', () {
    final p = PricingSettings.fromMap({
      'urgentSurchargePct': 'twenty',
      'nurseDailyRate': -5,
    });
    expect(p.urgentSurchargePct, isNull);
    expect(p.nurseDailyRate, isNull);
  });
}
