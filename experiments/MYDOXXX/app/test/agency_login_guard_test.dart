import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/physio_agency_service.dart';

void main() {
  test('experiment agency login stops before Firebase initialization or email', () async {
    // Deliberately do not initialize Firebase or any mock channel. Reaching
    // Auth would produce a Firebase initialization error instead of this guard.
    await expectLater(
      PhysioAgencyService.createAgencyLogin('agency@example.invalid'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('MYDOXXX experiment'),
      )),
    );
  });
}
