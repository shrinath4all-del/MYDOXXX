import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/config/test_lab_config.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/services/nurse_staffing_service.dart';
import 'package:mydox/services/service_otp.dart';
import 'package:mydox/services/sos_service.dart';
import 'package:mydox/services/technician_staffing_service.dart';

class ControlledRandom implements Random {
  ControlledRandom(this.value);
  final int value;
  int calls = 0;

  @override
  int nextInt(int max) {
    calls++;
    expect(max, 9000);
    return value;
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  test('compile-time lab uses 7777; normal generation preserves random range',
      () {
    for (final value in [0, 1, 8999]) {
      final random = ControlledRandom(value);
      expect(ServiceOtp.generate(random: random),
          TestLabConfig.enabled ? '7777' : '${1000 + value}');
      expect(random.calls, TestLabConfig.enabled ? 0 : 1);
    }
  });

  test('default service codes are four decimal digits without leading zero',
      () {
    for (var i = 0; i < 20; i++) {
      final code = ServiceOtp.generate();
      expect(code, matches(RegExp(r'^[1-9][0-9]{3}$')));
      if (TestLabConfig.enabled) expect(code, '7777');
    }
  });

  test('SOS patient/ambulance/hospital and doctor arrival use the same factory',
      () {
    for (var i = 0; i < 10; i++) {
      final code = SosService.newOtp();
      expect(code, matches(RegExp(r'^[1-9][0-9]{3}$')));
      if (TestLabConfig.enabled) expect(code, '7777');
    }
  });

  for (final entry in {
    'Care physician': CarePhysicianService.activeArrivalOtp,
    'Nurse': NurseStaffingService.activeArrivalOtp,
    'Technician': TechnicianStaffingService.activeArrivalOtp,
  }.entries) {
    test('${entry.key}: 7777 does not bypass arrival expiry or shift status',
        () {
      final now = DateTime(2026, 11, 3, 12);
      final shift = <String, dynamic>{
        'status': 'claimed',
        'arrivalOtp': '7777',
        'arrivalOtpAt': now.toIso8601String(),
      };
      expect(entry.value(shift, now), '7777');
      expect(entry.value(shift, now.add(const Duration(minutes: 11))), isNull);
      expect(entry.value({...shift, 'status': 'on_duty'}, now), isNull);
      expect(entry.value({...shift, 'arrivalOtpAt': null}, now), isNull);
      // Validation reads the record; the test constant is never substituted.
      expect(entry.value({...shift, 'arrivalOtp': '2468'}, now), '2468');
    });
  }
}
