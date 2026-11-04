import 'dart:math';

import '../config/test_lab_config.dart';

/// Arrival/consultation codes only; never used for Firebase phone sign-in.
/// The compile-time lab already restricts database access to synthetic records
/// in mydoxxx-testing. Validation still compares the booking's stored code.
class ServiceOtp {
  static String generate({Random? random}) {
    if (TestLabConfig.enabled) return '7777';
    return (1000 + (random ?? Random.secure()).nextInt(9000)).toString();
  }
}
