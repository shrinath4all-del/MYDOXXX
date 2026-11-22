import 'package:flutter_test/flutter_test.dart';

import '../lib/utils/admin_login_policy.dart';

void main() {
  const configuredEmail = 'admin@example.test';

  bool canEnter({String email = configuredEmail, Object? role}) =>
      canUseProvisionedAdminPortal(
        authenticatedEmail: email,
        configuredAdminEmail: configuredEmail,
        storedRole: role,
      );

  test('a matching email without an account role cannot bootstrap admin', () {
    expect(canEnter(), isFalse);
  });

  test('a publicly registered patient cannot promote itself by email match', () {
    expect(canEnter(role: 'patient'), isFalse);
  });

  test('the configured existing administrator remains usable', () {
    expect(canEnter(role: 'admin'), isTrue);
  });

  test('an admin record does not bypass the configured email restriction', () {
    expect(canEnter(email: 'other@example.test', role: 'admin'), isFalse);
  });

  test('a malformed role value does not authorize administration', () {
    expect(canEnter(role: ['admin']), isFalse);
  });

  test('email case differences do not lock out a provisioned administrator', () {
    expect(canEnter(email: 'ADMIN@example.test', role: 'admin'), isTrue);
  });

  test('an empty configured administrator email disables administrator login',
      () {
    expect(
      canUseProvisionedAdminPortal(
        authenticatedEmail: '',
        configuredAdminEmail: '',
        storedRole: 'admin',
      ),
      isFalse,
    );
  });
}
