import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/config/test_lab_config.dart';
import 'package:mydox/config/experiment_environment.dart';
import 'package:mydox/services/test_lab_payment.dart';
import 'package:mydox/screens/common/provider_patient_requests_screen.dart';

void main() {
  group('Runtime test login boundary', () {
    for (final url in ['http://localhost:8901/', 'http://127.0.0.1:8901/']) {
      test('accepts local host $url',
          () => expect(TestLabConfig.isLoopback(Uri.parse(url)), isTrue));
    }
    for (final url in [
      'https://mydoxxxx.netlify.app/',
      'http://localhost.evil.example/',
      'http://127.0.0.1.evil.example/',
      'http://user@localhost/',
      'file:///localhost/a'
    ]) {
      test('rejects non-loopback credential origin $url',
          () => expect(TestLabConfig.isLoopback(Uri.parse(url)), isFalse));
    }
    Map<String, dynamic> config(String key) => {
          'projectId': ExperimentEnvironment.projectId,
          'databaseId': TestLabConfig.databaseId,
          'roleKey': key,
          'role': TestLabConfig.roleForKey(key),
          'uid': 'mdxtest${key.replaceAll('_', '')}',
          'email': 'synthetic@mydoxxx-test.invalid',
          'password': 'test-only-fixture',
        };
    for (final key in TestLabConfig.labels.keys) {
      test(
          'accepts assigned $key config',
          () => expect(
              () => TestLabConfig.validateLoginConfig(config(key),
                  requestedRole: key),
              returnsNormally));
    }
    for (final change in <String, dynamic>{
      'projectId': 'mydox-be432',
      'databaseId': '(default)',
      'uid': 'copiedidentity',
      'role': 'admin',
      'roleKey': 'admin',
      'password': ''
    }.entries) {
      test(
          'rejects wrong ${change.key}',
          () => expect(
              () => TestLabConfig.validateLoginConfig(
                  {...config('patient'), change.key: change.value}),
              throwsStateError));
    }
    test(
        'a role panel cannot request a different login',
        () => expect(
            () => TestLabConfig.validateLoginConfig(config('doctor'),
                requestedRole: 'patient'),
            throwsStateError));
    test('catalogue has exactly three distinct identities in each family', () {
      expect(TestLabConfig.families.length, 12);
      expect(TestLabConfig.labels.length, 36);
      final uids = <String>{};
      for (final family in TestLabConfig.families.keys) {
        for (final key in [family, '${family}_2', '${family}_3']) {
          expect(TestLabConfig.labels.containsKey(key), isTrue);
          expect(TestLabConfig.familyForKey(key), family);
          expect(TestLabConfig.roleForKey(key),
              family.startsWith('agency_') ? 'agency' : family);
          uids.add(config(key)['uid'] as String);
        }
      }
      expect(uids.length, 36);
    });
    test('cardiologist display labels retain original doctor identities', () {
      for (var number = 1; number <= 3; number++) {
        final key = number == 1 ? 'doctor' : 'doctor_$number';
        expect(TestLabConfig.labels[key], 'Cardiologist $number');
        expect(TestLabConfig.roleForKey(key), 'doctor');
      }
      expect(TestLabConfig.roleForKey('cardiologist'), isNull);
    });
    for (final key in [
      'patient_1',
      'doctor_4',
      'doctor_2_2',
      'care_physician_99',
      'agency_admin',
      'agency_care_4',
      'admin',
      'pharmacy',
      ''
    ]) {
      test('unsupported account $key cannot resolve to a role', () {
        expect(TestLabConfig.roleForKey(key), isNull);
        expect(
            () => TestLabConfig.validateLoginConfig(config(key),
                requestedRole: key),
            throwsStateError);
      });
    }
    test('Doctor 2 cannot use Doctor 1 identity even with matching role', () {
      expect(
          () => TestLabConfig.validateLoginConfig(
              {...config('doctor_2'), 'uid': config('doctor')['uid']},
              requestedRole: 'doctor_2'),
          throwsStateError);
      expect(
          () => TestLabConfig.validateLoginConfig(config('doctor'),
              requestedRole: 'doctor_2'),
          throwsStateError);
    });
  });

  test('every application Firestore call uses the database boundary', () {
    final pattern = RegExp(r'FirebaseFirestore\s*\.\s*instance(?!For)');
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(pattern.hasMatch(file.readAsStringSync()), isFalse,
          reason: file.path);
      if (!file.path.endsWith('app_database.dart')) {
        expect(
            file.readAsStringSync().contains('FirebaseFirestore.instanceFor'),
            isFalse,
            reason: file.path);
      }
    }
  });

  group('No duplicate patient requests; eligible transitions only', () {
    final direct = <String, dynamic>{
      'doctorUid': 'mdxtestnurse',
      'status': 'Pending Home Visit'
    };
    test(
        'direct selected provider can accept',
        () => expect(
            ProviderPatientRequests.canClaim(direct, 'mdxtestnurse'), isTrue));
    test(
        'other provider cannot accept direct booking',
        () => expect(
            ProviderPatientRequests.canClaim(direct, 'mdxtesttechnician'),
            isFalse));
    test(
        'broadcast can be accepted',
        () => expect(
            ProviderPatientRequests.canClaim(
                {...direct, 'status': 'Broadcasted'}, 'mdxtestnurse'),
            isTrue));
    test(
        'declined provider cannot reclaim',
        () => expect(
            ProviderPatientRequests.canClaim({
              ...direct,
              'status': 'Broadcasted',
              'declinedBy': ['mdxtestnurse']
            }, 'mdxtestnurse'),
            isFalse));
    for (final status in [
      'Confirmed',
      'In Progress',
      'Completed',
      'Cancelled'
    ]) {
      test(
          'closed or assigned $status cannot claim again',
          () => expect(
              ProviderPatientRequests.canClaim(
                  {...direct, 'status': status}, 'mdxtestnurse'),
              isFalse));
    }
  });
  group('Simulated payments only advance own accepted unpaid booking', () {
    final booking = <String, dynamic>{
      'patientUid': 'mdxtestpatient',
      'status': 'Confirmed',
      'paymentStatus': 'pending'
    };
    test(
        'own accepted synthetic booking can simulate',
        () => expect(
            TestLabPayment.canSimulate(booking, 'mdxtestpatient'), isTrue));
    test(
        'provider cannot pay someone else booking',
        () => expect(
            TestLabPayment.canSimulate(booking, 'mdxtestdoctor'), isFalse));
    test(
        'non-synthetic uid cannot simulate',
        () => expect(
            TestLabPayment.canSimulate(
                {...booking, 'patientUid': 'realuser'}, 'realuser'),
            isFalse));
    test(
        'paid booking cannot pay twice',
        () => expect(
            TestLabPayment.canSimulate(
                {...booking, 'paymentStatus': 'paid'}, 'mdxtestpatient'),
            isFalse));
    test(
        'unaccepted booking cannot be paid',
        () => expect(
            TestLabPayment.canSimulate(
                {...booking, 'status': 'Pending Home Visit'}, 'mdxtestpatient'),
            isFalse));
  });
}
