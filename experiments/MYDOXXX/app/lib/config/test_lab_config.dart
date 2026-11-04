import 'experiment_environment.dart';

/// Compile-time only: a normal build cannot enable test access via a URL.
class TestLabConfig {
  static const enabled = bool.fromEnvironment('MYDOXXX_TEST_LAB');
  static const databaseId = 'mydoxxx-testing';
  static const families = <String, String>{
    'patient': 'Patient',
    'doctor': 'Cardiologist',
    'nurse': 'Nurse',
    'hospital': 'Hospital',
    'ambulance': 'Ambulance',
    'care_physician': 'Care Physician',
    'technician': 'Technician',
    'therapist': 'Therapist',
    'agency_care': 'Sai Care Agency',
    'agency_nurse': 'Nurse Agency',
    'agency_technician': 'Technician Agency',
    'agency_physio': 'Physio Agency',
  };

  /// Keep the original account key for person 1. Each suffix denotes a separate
  /// Firebase identity, not a second screen sharing another person's login.
  static final Map<String, String> labels = Map.unmodifiable({
    for (final family in families.entries)
      for (var number = 1; number <= 3; number++)
        (number == 1 ? family.key : '${family.key}_$number'):
            '${family.value} $number',
  });

  static String? familyForKey(Object? key) {
    if (key is! String || !labels.containsKey(key)) return null;
    return key.replaceFirst(RegExp(r'_[23]$'), '');
  }

  /// Only catalogue members may resolve to an application role. Do not accept
  /// arbitrary prefixes such as doctor_99 or agency_admin.
  static String? roleForKey(Object? key) {
    final family = familyForKey(key);
    if (family == null) return null;
    return family.startsWith('agency_') ? 'agency' : family;
  }

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
    final expectedRole = roleForKey(key);
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
