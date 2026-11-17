import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/verification_service.dart';

/// From the IT team's update (17 Nov 2026): documents over 10 MB are refused
/// before upload. Their duplicate-file (fingerprint) cases are not included
/// until that part is approved (it needs the `crypto` package).
void main() {
  final pan = List<int>.generate(2000, (i) => (i * 7) % 256);

  test('a normal file can be uploaded', () {
    expect(VerificationService.uploadProblem(pan, 'pan', const {}), isNull);
  });

  test('files over 10 MB are refused, 10 MB is fine', () {
    final ten = List<int>.filled(10 * 1024 * 1024, 1);
    expect(VerificationService.uploadProblem(ten, 'pan', const {}), isNull);
    expect(VerificationService.uploadProblem([...ten, 1], 'pan', const {}),
        contains('larger than 10 MB'));
  });

  test('the refusal message is shown to the user as it is', () {
    const e = DocumentUploadException('This file is larger than 10 MB.');
    expect(e.toString(), 'This file is larger than 10 MB.');
  });
}
