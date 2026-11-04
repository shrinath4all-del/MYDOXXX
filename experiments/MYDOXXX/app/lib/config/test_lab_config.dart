import 'experiment_environment.dart';

/// Compile-time only: a normal build cannot enable test access via a URL.
class TestLabConfig {
  static const enabled = bool.fromEnvironment('MYDOXXX_TEST_LAB');
  static const databaseId = 'mydoxxx-testing';
  static const labels = <String, String>{
    'patient': 'Patient',
    'doctor': 'Doctor',
    'nurse': 'Nurse',
    'hospital': 'Hospital',
    'ambulance': 'Ambulance',
    'care_physician': 'Care Physician',
    'care_physician_2': 'Care Physician 2',
    'care_physician_3': 'Care Physician 3',
    'technician': 'Technician',
    'therapist': 'Therapist',
    'agency_care': 'Sai Care Agency',
    'agency_nurse': 'Nurse Agency',
    'agency_technician': 'Technician Agency',
    'agency_physio': 'Physio Agency',
  };

  static bool isLoopback(Uri uri) =>
      const {'http', 'https'}.contains(uri.scheme) &&
      const {'localhost', '127.0.0.1', '::1'}.contains(uri.host) &&
      uri.userInfo.isEmpty;

  static void requireLocal(Uri uri) {
    if (!enabled || !isLoopback(uri)) {
      throw StateError(
          'Test logins are available only in the local MYDOXXX test lab.');
    }
  }

  /// Runtime credentials come only from the local role-specific server.
  /// Never include this object in logs, build assets, URLs or error messages.
  static void validateLoginConfig(Map<String, dynamic> data,
      {String? requestedRole}) {
    final key = data['roleKey'] ?? data['role'];
    final expectedRole = key is String && key.startsWith('agency_')
        ? 'agency'
        : (key is String && key.startsWith('care_physician_')
            ? 'care_physician'
            : key);
    if (data['projectId'] != ExperimentEnvironment.projectId ||
        data['databaseId'] != databaseId ||
        !labels.containsKey(key) ||
        data['role'] != expectedRole ||
        data['uid'] != 'mdxtest${key.toString().replaceAll('_', '')}' ||
        (requestedRole != null &&
            requestedRole.isNotEmpty &&
            requestedRole != key) ||
        data['email'] is! String ||
        data['password'] is! String ||
        (data['password'] as String).isEmpty) {
      throw StateError(
          'The local role configuration does not match this test panel.');
    }
  }
}
