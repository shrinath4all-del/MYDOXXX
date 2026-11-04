import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/config/experiment_environment.dart';
import 'package:mydox/config/test_lab_config.dart';
import 'package:mydox/screens/test_lab/test_lab_cloud_bridge_stub.dart';

void main() {
  const portal = 'https://mydoxxx-live-test.netlify.app';
  final now = DateTime.utc(2026, 11, 4, 12);
  Map<String, dynamic> login(String key) => {
        'projectId': ExperimentEnvironment.projectId,
        'databaseId': TestLabConfig.databaseId,
        'roleKey': key,
        'role': TestLabConfig.roleForKey(key),
        'uid': 'mdxtest${key.replaceAll('_', '')}',
        'customToken': 'synthetic.token.fixture',
      };
  Map<String, dynamic> claims() => {
        'cloudLab': true,
        'labOperatorUid': 'synthetic-owner',
        'labExpiresAt':
            now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      };

  group('Exact cloud panel boundary', () {
    test('only approved HTTPS origin and /panel/ entry are accepted', () {
      expect(TestLabConfig.isCloudPanel(Uri.parse('$portal/panel/')), isTrue);
      expect(
          TestLabConfig.isCloudPanel(
              Uri.parse('$portal/panel/?role=doctor_2&autologin=1')),
          isTrue);
    });
    for (final url in [
      '$portal/',
      '$portal/panel',
      '$portal/panel/index.html',
      '$portal/panel/other',
      '$portal:8443/panel/',
      'http://mydoxxx-live-test.netlify.app/panel/',
      'https://mydoxxxx.netlify.app/panel/',
      'https://other-lab.netlify.app/panel/',
      'https://mydoxxx-live-test.netlify.app.evil.example/panel/',
      'https://user@mydoxxx-live-test.netlify.app/panel/',
      'https://mydoxxx-live-test.netlify.app@evil.example/panel/',
      'https://deploy-preview-1--mydoxxx-live-test.netlify.app/panel/',
      'http://localhost:8891/panel/',
      'file:///panel/',
    ]) {
      test('rejects $url', () {
        expect(TestLabConfig.isCloudPanel(Uri.parse(url)), isFalse);
      });
    }
    test('compile-time flags select the environment; query cannot enable it',
        () {
      final remote = Uri.parse('$portal/panel/?MYDOXXX_TEST_LAB=true');
      final local = Uri.parse('http://localhost:8891/?role=patient');
      expect(
          () => TestLabConfig.requireEnvironment(remote),
          TestLabConfig.enabled && TestLabConfig.cloudEnabled
              ? returnsNormally
              : throwsStateError);
      expect(
          () => TestLabConfig.requireEnvironment(local),
          TestLabConfig.enabled && !TestLabConfig.cloudEnabled
              ? returnsNormally
              : throwsStateError);
      // Cloud support never broadens the explicitly local-only API.
      expect(() => TestLabConfig.requireLocal(remote), throwsStateError);
    });
  });

  group('Ephemeral role envelope', () {
    for (final key in TestLabConfig.labels.keys) {
      test('accepts matching $key identity', () {
        expect(
            () => TestLabConfig.validateCloudLoginConfig(login(key),
                requestedRole: key),
            returnsNormally);
      });
    }
    for (final change in <String, dynamic>{
      'projectId': 'mydox-be432',
      'databaseId': '(default)',
      'roleKey': 'doctor_2',
      'role': 'admin',
      'uid': 'mdxtestdoctor2',
      'customToken': '',
      'password': 'must-not-enter-cloud-panel',
      'email': 'must-not-enter-cloud-panel@example.invalid',
    }.entries) {
      test('rejects mismatched or forbidden ${change.key}', () {
        expect(
            () => TestLabConfig.validateCloudLoginConfig(
                {...login('patient'), change.key: change.value},
                requestedRole: 'patient'),
            throwsStateError);
      });
    }
    for (final key in ['', 'admin', 'patient_1', 'patient_4', 'doctor']) {
      test('cannot use patient identity in panel "$key"', () {
        expect(
            () => TestLabConfig.validateCloudLoginConfig(login('patient'),
                requestedRole: key),
            throwsStateError);
      });
    }
    test('rejects malformed token values without surfacing their contents', () {
      for (final token in [null, 123, 'has whitespace', 'x' * 16385]) {
        expect(
            () => TestLabConfig.validateCloudLoginConfig(
                {...login('patient'), 'customToken': token},
                requestedRole: 'patient'),
            throwsStateError);
      }
    });
    test('native bridge cannot return cloud credentials', () async {
      await expectLater(requestCloudLogin('patient'), throwsStateError);
    });
  });

  group('Signed cloud session claims', () {
    test('accepts broker 8-hour operator session', () {
      expect(() => TestLabConfig.validateCloudClaims(claims(), now: now),
          returnsNormally);
    });
    for (final field in ['cloudLab', 'labOperatorUid', 'labExpiresAt']) {
      test('missing $field is rejected', () {
        final value = claims()..remove(field);
        expect(() => TestLabConfig.validateCloudClaims(value, now: now),
            throwsStateError);
      });
    }
    for (final invalid in [
      null,
      'tomorrow',
      double.nan,
      double.infinity,
      now.millisecondsSinceEpoch,
      now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      now.add(const Duration(hours: 1)).millisecondsSinceEpoch + 0.5,
    ]) {
      test('rejects invalid expiry $invalid', () {
        expect(
            () => TestLabConfig.validateCloudClaims(
                {...claims(), 'labExpiresAt': invalid},
                now: now),
            throwsStateError);
      });
    }
    test('rejects missing cloud permission and empty operator', () {
      for (final value in [
        {...claims(), 'cloudLab': false},
        {...claims(), 'cloudLab': 'true'},
        {...claims(), 'labOperatorUid': '   '},
        {...claims(), 'labOperatorUid': 123},
      ]) {
        expect(() => TestLabConfig.validateCloudClaims(value, now: now),
            throwsStateError);
      }
    });
  });
}
