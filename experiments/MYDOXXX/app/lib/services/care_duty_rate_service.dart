import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_database.dart';
import '../utils/ist_clock.dart';

/// What a hospital pays for one kind of care physician duty, and how that
/// money is shared. The prices live in the Firestore master table
/// `care_duty_rates/{ward|icu|specialty}` (edited in the Firebase console;
/// nothing is typed into the app by the hospital):
///
///   hospitalRate        ₹ the hospital pays for one duty (a locum shift)
///   monthlySalary       ₹ the hospital pays per month for a full-time
///                       care physician of this duty type (a team)
///   platformMarginPct   % of it kept back (the physician gets the rest)
///   saiSharePct         % of that margin that goes to Sai Services
///   mydoxSharePct       % of that margin that goes to MyDox
///
/// Example: ₹2,000 with a 15 % margin: the care physician is paid ₹1,700 and
/// sees ₹1,700; the ₹300 margin splits ₹225 Sai Services and ₹75 MyDox.
/// A hospital's size, set by the admin when the hospital is verified (and
/// changed only by the admin). It decides the price of a duty.
class HospitalCategory {
  HospitalCategory._();

  static const String small = 'small';
  static const String medium = 'medium';
  static const String high = 'high';
  static const List<String> all = [small, medium, high];

  /// A hospital the admin has not categorised yet is treated as medium.
  static const String fallback = medium;

  static String label(String c) => switch (c) {
        small => 'Small',
        high => 'High',
        _ => 'Medium',
      };

  static String normalize(Object? c) {
    final v = (c ?? '').toString().toLowerCase().trim();
    return all.contains(v) ? v : fallback;
  }

  /// ₹ per duty: category -> duty type -> rate. The specialty duty (pediatric
  /// ward) is priced like ICU; casualty has the old specialty prices.
  static const Map<String, Map<String, int>> dutyRates = {
    small: {'icu': 1500, 'ward': 1100, 'casualty': 1200, 'specialty': 1500},
    medium: {'icu': 2000, 'ward': 1500, 'casualty': 1800, 'specialty': 2000},
    high: {'icu': 2500, 'ward': 1700, 'casualty': 2000, 'specialty': 2500},
  };

  static int? rateFor(String category, String dutyType) =>
      dutyRates[normalize(category)]?[dutyType];
}

class CareDutyRate {
  final String dutyType;
  final String label;
  final int hospitalRate;
  final int? monthlySalary;
  final num platformMarginPct;
  final num saiSharePct;
  final num mydoxSharePct;
  final Map<String, num> categoryRates;

  const CareDutyRate({
    required this.dutyType,
    required this.label,
    required this.hospitalRate,
    this.monthlySalary,
    this.platformMarginPct = 15,
    this.saiSharePct = 75,
    this.mydoxSharePct = 25,
    this.categoryRates = const {},
  });

  /// The part of the rate kept back (whole rupees).
  int get margin => (hospitalRate * platformMarginPct / 100).round();

  /// What the care physician is paid and sees.
  int get doctorPay => hospitalRate - margin;

  int get saiShare =>
      (margin * saiSharePct / (saiSharePct + mydoxSharePct)).round();

  int get mydoxShare => margin - saiShare;

  num get _saiOfMargin => saiSharePct / (saiSharePct + mydoxSharePct);

  /// The same margin and split on the monthly salary of a full-time team.
  int get monthlyMargin =>
      ((monthlySalary ?? 0) * platformMarginPct / 100).round();
  int get monthlyDoctorPay => (monthlySalary ?? 0) - monthlyMargin;
  int get monthlySaiShare => (monthlyMargin * _saiOfMargin).round();
  int get monthlyMydoxShare => monthlyMargin - monthlySaiShare;

  /// The same duty priced for a hospital of [category]: the master table can
  /// override it with `categoryRates: {small, medium, high}`, otherwise the
  /// standard category rates apply.
  CareDutyRate forCategory(Object? category, [Map<String, dynamic>? doc]) {
    final c = HospitalCategory.normalize(category);
    final o = _categoryRates(doc?['categoryRates'])[c] ?? categoryRates[c];
    final rate = o is num && o.isFinite && o > 0 && o.round() > 0
        ? o.round()
        : (HospitalCategory.rateFor(c, dutyType) ?? hospitalRate);
    return CareDutyRate(
      dutyType: dutyType,
      label: label,
      hospitalRate: rate,
      monthlySalary: monthlySalary,
      platformMarginPct: platformMarginPct,
      saiSharePct: saiSharePct,
      mydoxSharePct: mydoxSharePct,
      categoryRates: categoryRates,
    );
  }

  static Map<String, num> _categoryRates(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final c in HospitalCategory.all)
        if (value[c] is num &&
            (value[c] as num).isFinite &&
            (value[c] as num) > 0 &&
            (value[c] as num).round() > 0)
          c: value[c] as num,
    });
  }

  static CareDutyRate? fromDoc(String id, Map<String, dynamic>? m) {
    if (m == null || m['active'] == false) return null;
    final rate = m['hospitalRate'];
    if (rate is! num || !rate.isFinite || rate <= 0 || rate.round() <= 0) {
      return null;
    }
    num pct(String k, num fallback) {
      final v = m[k];
      return v is num && v.isFinite && v >= 0 ? v : fallback;
    }

    final platform = pct('platformMarginPct', 15);
    final sai = pct('saiSharePct', 75);
    final mydox = pct('mydoxSharePct', 25);
    if (platform > 100 || sai + mydox <= 0) return null;
    final salary = m['monthlySalary'];
    return CareDutyRate(
      dutyType: id,
      label: (m['label'] ?? id).toString(),
      hospitalRate: rate.round(),
      monthlySalary: salary is num && salary.isFinite && salary > 0 && salary.round() > 0
          ? salary.round()
          : null,
      platformMarginPct: platform,
      saiSharePct: sai,
      mydoxSharePct: mydox,
      categoryRates: _categoryRates(m['categoryRates']),
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

/// What a full-time team costs per month, and what each care physician is
/// paid: the same fields as a locum shift, for one month.
extension CareDutyRateMonthly on CareDutyRate {
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

class CareDutyRates {
  CareDutyRates._();

  static const String collection = 'care_duty_rates';

  /// Shown when a duty type has no price in the master table.
  static const String notSetMessage =
      'The rate for this duty is not set yet. Please try again later or contact support.';

  /// Duty types that are priced from another master-table document: the
  /// specialty (pediatric ward) duty like ICU, casualty like the old
  /// specialty duty.
  static const Map<String, String> sourceDoc = {
    'specialty': 'icu',
    'casualty': 'specialty',
  };

  static CareDutyRate _as(CareDutyRate r, String dutyType) => CareDutyRate(
        dutyType: dutyType,
        label: r.label,
        hospitalRate: r.hospitalRate,
        monthlySalary: r.monthlySalary,
        platformMarginPct: r.platformMarginPct,
        saiSharePct: r.saiSharePct,
        mydoxSharePct: r.mydoxSharePct,
        categoryRates: r.categoryRates,
      );

  static Stream<Map<String, CareDutyRate>> stream() =>
      AppDatabase.instance.collection(collection).snapshots().map(
            (s) =>
                fromMasterDocuments({for (final d in s.docs) d.id: d.data()}),
          );

  /// Build streamed quotes with the same source mapping used at submission.
  /// Keep category overrides on the model so the form can price its category.
  static Map<String, CareDutyRate> fromMasterDocuments(
    Map<String, Map<String, dynamic>> documents,
  ) {
    final result = <String, CareDutyRate>{};
    final types = {
      ...HospitalCategory.dutyRates[HospitalCategory.fallback]!.keys,
      ...documents.keys,
    };
    for (final type in types) {
      final rate = fromMasterDocument(type, documents[sourceDoc[type] ?? type]);
      if (rate != null) result[type] = rate;
    }
    return result;
  }

  /// Missing master documents use the new category defaults. An explicitly
  /// disabled or invalid document remains unavailable instead of resurfacing.
  static CareDutyRate? fromMasterDocument(
    String dutyType,
    Map<String, dynamic>? document, {
    String? category,
  }) {
    final parsed = document == null
        ? _standard(dutyType)
        : CareDutyRate.fromDoc(dutyType, document);
    if (parsed == null) return null;
    final base = _as(parsed, dutyType);
    return category == null ? base : base.forCategory(category);
  }

  /// The rate for [dutyType], read now (null while it is not set). With a
  /// hospital [category] it is that category's price.
  static Future<CareDutyRate?> load(String dutyType, {String? category}) async {
    final d = await AppDatabase.instance
        .collection(collection)
        .doc(sourceDoc[dutyType] ?? dutyType)
        .get();
    return fromMasterDocument(dutyType, d.data(), category: category);
  }

  static CareDutyRate? _standard(String dutyType) {
    final r = HospitalCategory.rateFor(HospitalCategory.fallback, dutyType);
    return r == null
        ? null
        : CareDutyRate(dutyType: dutyType, label: dutyType, hospitalRate: r);
  }

  /// A hospital's category (medium until the admin sets one).
  static Future<String> categoryOf(String hospitalId) async {
    if (hospitalId.isEmpty) return HospitalCategory.fallback;
    final d = await AppDatabase.instance
        .collection('hospitals')
        .doc(hospitalId)
        .get();
    return HospitalCategory.normalize(d.data()?['rateCategory']);
  }

  static Stream<String> categoryStream(String hospitalId) =>
      AppDatabase.instance
          .collection('hospitals')
          .doc(hospitalId)
          .snapshots()
          .map((d) => HospitalCategory.normalize(d.data()?['rateCategory']));

  /// The admin sets (or changes) a hospital's category.
  static Future<void> setCategory(String hospitalId, String category) =>
      AppDatabase.instance.collection('hospitals').doc(hospitalId).set({
        'rateCategory': HospitalCategory.normalize(category),
        'rateCategoryAt': IstClock.now().toIso8601String(),
      }, SetOptions(merge: true));
}
