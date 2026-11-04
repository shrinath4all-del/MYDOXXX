import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/physio_agency_service.dart';

void main() {
  test('agency login matches the last 10 digits of the mobile number', () {
    expect(PhysioAgencyService.phoneKey('+91 93077 33042'), '9307733042');
    expect(PhysioAgencyService.phoneKey('+919307733042'), '9307733042');
    expect(PhysioAgencyService.phoneKey('09307733042'), '9307733042');
    expect(PhysioAgencyService.phoneKey('9307733042'), '9307733042');
  });
}
