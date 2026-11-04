/// Texts used on many screens. Screen-specific wording stays in the screen;
/// anything repeated (buttons, labels, common messages) lives here.
class AppStrings {
  AppStrings._();

  static const String appName = 'MyDox';

  // Buttons
  static const String cancel = 'Cancel';
  static const String confirm = 'Yes, Confirm';
  static const String ok = 'OK';
  static const String done = 'Done';
  static const String close = 'Close';
  static const String save = 'Save';
  static const String retry = 'Try again';
  static const String chat = 'Chat';
  static const String call = 'Call';
  static const String logout = 'Log out';
  static const String notifications = 'Notifications';

  // Login roles: one name per role for chips and buttons
  static const Map<String, String> roleNames = {
    'patient': 'Patient',
    'hospital': 'Hospital',
    'doctor': 'Doctor',
    'ambulance': 'Ambulance',
    'technician': 'Technician',
    'therapist': 'Therapist',
    'nurse': 'Nurse',
    'care_physician': 'Care Physician',
    'agency': 'Partner',
    'admin': 'Admin',
  };

  static String roleName(String role) => roleNames[role] ?? 'Patient';
  static String loginAs(String role) => 'Login as ${roleName(role)}';
  static String registerAs(String role) => 'Register as ${roleName(role)}';

  // Chat
  static const String chatLocked =
      'Chat opens when the consultation ends.';
  static const String chatExpired =
      'Chat was open for 24 hours after the consultation.';

  // Fees
  static const String baseFee = 'Base fee';
  static const String urgentSurcharge = 'Urgent surcharge';
  static const String homeVisitCharge = 'Home visit charge';
  static const String totalFee = 'Total fee';

  // Search
  static const String search = 'Search';
  static const String listening = 'Listening…';
  static const String voiceUnavailable =
      'Voice search is not available on this phone.';

  // Emergency
  static const String emergencyActive = 'Emergency in progress';
  static const String emergencyActiveHint = 'Tap to see your emergency';
}
