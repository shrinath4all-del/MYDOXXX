import 'experiment_environment.dart';

/// Compile-time only: a normal build cannot enable test access via a URL.
class TestLabConfig {
  static const enabled = bool.fromEnvironment('MYDOXXX_TEST_LAB');
  static const cloudEnabled = bool.fromEnvironment('MYDOXXX_CLOUD_TEST_LAB');
  static const cloudOrigin = String.fromEnvironment('MYDOXXX_TEST_ORIGIN',
      defaultValue: 'https://mydoxxx-live-test.netlify.app');
  static const _approvedCloudOrigin = 'https://mydoxxx-live-test.netlify.app';
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

  /// A cloud build is restricted to this reviewed portal and its panel entry.
  /// Runtime query parameters cannot enable cloud access or choose a host.
  static bool isCloudPanel(Uri uri) =>
      cloudOrigin == _approvedCloudOrigin &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.origin == cloudOrigin &&
      uri.path == '/panel/';

  static void requireEnvironment(Uri uri) {
    if (cloudEnabled) {
      if (!enabled || !isCloudPanel(uri)) {
        throw StateError(
            'Cloud test logins require the approved MYDOXXX test portal.');
      }
      return;
    }
    requireLocal(uri);
  }

  static bool _matchesIdentity(
      Map<String, dynamic> data, String? requestedRole) {
    final key = data['roleKey'] ?? data['role'];
    return data['projectId'] == ExperimentEnvironment.projectId &&
        data['databaseId'] == databaseId &&
        labels.containsKey(key) &&
        data['role'] == roleForKey(key) &&
        data['uid'] == 'mdxtest${key.toString().replaceAll('_', '')}' &&
        (requestedRole == null ||
            requestedRole.isEmpty ||
            requestedRole == key);
  }

  /// Runtime credentials come only from the local role-specific server.
  /// Never include this object in logs, build assets, URLs or error messages.
  static void validateLoginConfig(Map<String, dynamic> data,
      {String? requestedRole}) {
    if (!_matchesIdentity(data, requestedRole) ||
        data['email'] is! String ||
        data['password'] is! String ||
        (data['password'] as String).isEmpty) {
      throw StateError(
          'The local role configuration does not match this test panel.');
    }
  }

  /// The owner-authenticated portal supplies one ephemeral Firebase custom
  /// token to the requesting frame. No password or owner token enters Flutter.
  static void validateCloudLoginConfig(Map<String, dynamic> data,
      {required String requestedRole}) {
    final customToken = data['customToken'];
    if (!labels.containsKey(requestedRole) ||
        !_matchesIdentity(data, requestedRole) ||
        data['roleKey'] != requestedRole ||
        data.containsKey('email') ||
        data.containsKey('password') ||
        customToken is! String ||
        customToken.isEmpty ||
        customToken.length > 16384 ||
        RegExp(r'\s').hasMatch(customToken)) {
      throw StateError(
          'The cloud role configuration does not match this test panel.');
    }
  }

  /// Defence in depth after Firebase verifies the token signature. The broker
  /// and Firestore rules must also enforce this expiry on the server.
  static void validateCloudClaims(Map<String, dynamic> claims,
      {DateTime? now}) {
    final operatorUid = claims['labOperatorUid'];
    final expiresAt = claims['labExpiresAt'];
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final latestMs =
        nowMs + const Duration(hours: 8, minutes: 5).inMilliseconds;
    if (claims['cloudLab'] != true ||
        operatorUid is! String ||
        operatorUid.trim().isEmpty ||
        operatorUid.length > 128 ||
        expiresAt is! num ||
        !expiresAt.isFinite ||
        expiresAt != expiresAt.roundToDouble() ||
        expiresAt <= nowMs ||
        expiresAt > latestMs) {
      throw StateError(
          'The cloud test session is invalid or expired. Reopen the test portal.');
    }
  }
}
