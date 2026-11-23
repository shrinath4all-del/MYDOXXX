import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/validators.dart';

void main() {
  test('a doctor registration number is 12 letters and/or numbers', () {
    for (final ok in ['MMC201908421', '201908421345', 'mmc201908421', 'ABCD12345678']) {
      expect(Validators.medicalRegistration(ok), isNull, reason: ok);
    }
  });

  test('anything else is refused', () {
    for (final bad in [
      '', 'MMC2019084', 'MMC2019084210', 'MMC-2019-0842', 'MMC/20190842', 'MMC 2019 0842@',
      '000000000000', 'AAAAAAAAAAAA', '123456789012',
    ]) {
      expect(Validators.medicalRegistration(bad), isNotNull, reason: bad);
    }
  });

  test('how many were typed is shown', () {
    expect(Validators.medicalRegistration('MMC2019'), contains('7 entered'));
  });

  test('the same number typed differently is one number', () {
    expect(Validators.registrationKey('mmc201908421'),
        Validators.registrationKey('MMC201908421'));
  });
}
