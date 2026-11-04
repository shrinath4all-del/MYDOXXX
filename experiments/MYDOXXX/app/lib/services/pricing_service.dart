import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Booking prices that are not part of a service list, from Firestore
/// `app_settings/pricing` (edited in the Firebase console; nothing is typed
/// into the app). The server works the price out again from the same data,
/// so what the phone shows is only a preview.
///
///   urgentSurchargePct    % added to an urgent doctor / therapy booking
///   doctorHomeVisitExtra  ₹ added to a (not urgent) doctor home visit
///   nurseDailyRate        ₹ per nursing day
///   sosEmergencyFee       ₹ for an SOS emergency
///   emergencyLocumHikePct % added to an agency's emergency locum duty
class PricingSettings {
  final num? urgentSurchargePct;
  final int? doctorHomeVisitExtra;
  final int? nurseDailyRate;
  final int? sosEmergencyFee;
  final num? emergencyLocumHikePct;

  const PricingSettings({
    this.urgentSurchargePct,
    this.doctorHomeVisitExtra,
    this.nurseDailyRate,
    this.sosEmergencyFee,
    this.emergencyLocumHikePct,
  });

  factory PricingSettings.fromMap(Map<String, dynamic>? m) {
    int? whole(dynamic v) => v is num && v >= 0 ? v.round() : null;
    final pct = m?['urgentSurchargePct'];
    final hike = m?['emergencyLocumHikePct'];
    return PricingSettings(
      urgentSurchargePct: pct is num && pct >= 0 ? pct : null,
      doctorHomeVisitExtra: whole(m?['doctorHomeVisitExtra']),
      nurseDailyRate: whole(m?['nurseDailyRate']),
      sosEmergencyFee: whole(m?['sosEmergencyFee']),
      emergencyLocumHikePct: hike is num && hike >= 0 ? hike : null,
    );
  }

  /// Urgent surcharge on [base] (null while the % is not set).
  int? urgentSurcharge(int base) => urgentSurchargePct == null
      ? null
      : (base * urgentSurchargePct! / 100).round();

  /// Billed rate of an agency duty: an emergency locum costs the hospital
  /// [emergencyLocumHikePct] more than the agency's rate (same as the server).
  int billedRate(String type, num baseRate) => type == 'emergency' &&
          emergencyLocumHikePct != null
      ? (baseRate * (100 + emergencyLocumHikePct!) / 100).round()
      : baseRate.round();

  /// Same as the server: whole rupees, [days] at least 1.
  int? nurseFee(int days) =>
      nurseDailyRate == null ? null : nurseDailyRate! * (days < 1 ? 1 : days);
}

class PricingService {
  static DocumentReference<Map<String, dynamic>> get _doc =>
      AppDatabase.instance.collection('app_settings').doc('pricing');

  /// Latest settings seen (empty until the first read).
  static PricingSettings current = const PricingSettings();

  static Future<PricingSettings> load() async {
    try {
      current = PricingSettings.fromMap((await _doc.get()).data());
    } catch (_) {}
    return current;
  }

  static Stream<PricingSettings> stream() => _doc.snapshots().map((s) {
        current = PricingSettings.fromMap(s.data());
        return current;
      });

  /// Shown when a price is missing in Firestore.
  static const String notSetMessage =
      'The price for this service is not set yet. Please try again later or contact support.';
}
