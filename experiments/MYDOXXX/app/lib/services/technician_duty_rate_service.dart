import 'app_database.dart';

/// What a hospital pays for one kind of technician duty, and how that
/// money is shared. The prices live in the Firestore master table
/// `technician_duty_rates/{ward|icu|specialty}` (edited in the Firebase console;
/// nothing is typed into the app by the hospital):
///
///   hospitalRate        ₹ the hospital pays for one duty (a locum shift)
///   monthlySalary       ₹ the hospital pays per month for a full-time
///                       technician of this duty type (a team)
///   platformMarginPct   % of it kept back (the physician gets the rest)
///   saiSharePct         % of that margin that goes to Sai Services
///   mydoxSharePct       % of that margin that goes to MyDox
///
/// Example: ₹2,000 with a 15 % margin: the technician is paid ₹1,700 and
/// sees ₹1,700; the ₹300 margin splits ₹225 Sai Services and ₹75 MyDox.
class TechnicianDutyRate {
  final String dutyType;
  final String label;
  final int hospitalRate;
  final int? monthlySalary;
  final num platformMarginPct;
  final num saiSharePct;
  final num mydoxSharePct;

  const TechnicianDutyRate({
    required this.dutyType,
    required this.label,
    required this.hospitalRate,
    this.monthlySalary,
    this.platformMarginPct = 15,
    this.saiSharePct = 75,
    this.mydoxSharePct = 25,
  });

  /// The part of the rate kept back (whole rupees).
  int get margin => (hospitalRate * platformMarginPct / 100).round();

  /// What the technician is paid and sees.
  int get doctorPay => hospitalRate - margin;

  int get saiShare => (margin * saiSharePct / (saiSharePct + mydoxSharePct)).round();

  int get mydoxShare => margin - saiShare;

  num get _saiOfMargin => saiSharePct / (saiSharePct + mydoxSharePct);

  /// The same margin and split on the monthly salary of a full-time team.
  int get monthlyMargin => ((monthlySalary ?? 0) * platformMarginPct / 100).round();
  int get monthlyDoctorPay => (monthlySalary ?? 0) - monthlyMargin;
  int get monthlySaiShare => (monthlyMargin * _saiOfMargin).round();
  int get monthlyMydoxShare => monthlyMargin - monthlySaiShare;

  static TechnicianDutyRate? fromDoc(String id, Map<String, dynamic>? m) {
    if (m == null || m['active'] == false) return null;
    final rate = m['hospitalRate'];
    if (rate is! num || rate <= 0) return null;
    num pct(String k, num fallback) {
      final v = m[k];
      return v is num && v >= 0 ? v : fallback;
    }

    return TechnicianDutyRate(
      dutyType: id,
      label: (m['label'] ?? id).toString(),
      hospitalRate: rate.round(),
      monthlySalary: m['monthlySalary'] is num && (m['monthlySalary'] as num) > 0
          ? (m['monthlySalary'] as num).round()
          : null,
      platformMarginPct: pct('platformMarginPct', 15),
      saiSharePct: pct('saiSharePct', 75),
      mydoxSharePct: pct('mydoxSharePct', 25),
    );
  }

  /// The fields written on a shift: the hospital's price, the care
  /// physician's pay and the shares (the physician's screens read 'doctorPay').
  Map<String, dynamic> toShiftFields() => {
        'pay': hospitalRate,
        'doctorPay': doctorPay,
        'marginAmount': margin,
        'saiShare': saiShare,
        'mydoxShare': mydoxShare,
        'rateSource': 'master',
      };
}

/// What a full-time team costs per month, and what each technician is
  /// paid: the same fields as a locum shift, for one month.
extension TechnicianDutyRateMonthly on TechnicianDutyRate {
  Map<String, dynamic> toTeamFields() => {
        'pay': monthlySalary,
        'doctorPay': monthlyDoctorPay,
        'marginAmount': monthlyMargin,
        'saiShare': monthlySaiShare,
        'mydoxShare': monthlyMydoxShare,
        'rateSource': 'master',
        'payPeriod': 'month',
      };
}

class TechnicianDutyRates {
  TechnicianDutyRates._();

  static const String collection = 'technician_duty_rates';

  /// Shown when a duty type has no price in the master table.
  static const String notSetMessage =
      'The rate for this duty is not set yet. Please try again later or contact support.';

  static Stream<Map<String, TechnicianDutyRate>> stream() => AppDatabase.instance
          .collection(collection)
          .snapshots()
          .map((s) => {
                for (final d in s.docs)
                  if (TechnicianDutyRate.fromDoc(d.id, d.data()) != null)
                    d.id: TechnicianDutyRate.fromDoc(d.id, d.data())!
              });

  /// The rate for [dutyType], read now (null while it is not set).
  static Future<TechnicianDutyRate?> load(String dutyType) async {
    final d = await AppDatabase.instance
        .collection(collection)
        .doc(dutyType)
        .get();
    return TechnicianDutyRate.fromDoc(d.id, d.data());
  }
}
