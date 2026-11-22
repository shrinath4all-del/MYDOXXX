import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/auth_service.dart';
import 'package:mydox/utils/validators.dart';

void main() {
  test('one mobile number, however it is typed, is the same number', () {
    for (final typed in ['9876543210', '+91 98765 43210', '919876543210', '09876543210', '+91-98765-43210']) {
      expect(AuthService.phoneKey(typed), '9876543210', reason: typed);
    }
  });

  test('the password rule is explained in one message', () {
    const msg = 'Password must be at least 8 characters with at least one letter and one number';
    expect(Validators.newPassword('short1'), msg);
    expect(Validators.newPassword('onlyletters'), msg);
    expect(Validators.newPassword('12345678'), msg);
    expect(Validators.newPassword('good pass1'), 'Password cannot contain spaces');
    expect(Validators.newPassword('goodpass1'), isNull);
  });
}
