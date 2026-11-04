import '../models/care_duty_roster.dart';
import '../utils/safe_cast.dart';

/// Earnings from care physician duties, worked out from the agency duty
/// records (`duties`): each completed duty carries the split of its price.
///
///   hospitalRate  ₹ the hospital paid
///   doctorPay     ₹ the care physician is paid
///   appShare      ₹ MyDox keeps (25 % of the platform margin)
///   agencyShare   ₹ Sai Services (the agency) keeps (75 % of the margin)
///
/// A duty earns when it is completed (the physician checked in and out).
class CareEarnings {
  CareEarnings._();

  /// MyDox's share (what the admin sees).
  static const String mydox = 'appShare';

  /// Sai Services' share (what the agency sees).
  static const String sai = 'agencyShare';

  /// Today's date in India, "2026-10-23".
  static String dayKey(DateTime now) =>
      DutySlot.dateKey(CareDutyClock.today(now));

  static bool earned(Map<String, dynamic> d) => d['status'] == 'completed';

  /// Worked on the day: checked in (still on duty) or completed.
  static bool worked(Map<String, dynamic> d) =>
      d['status'] == 'on_duty' || d['status'] == 'completed';

  static int amount(Map<String, dynamic> d, String field) =>
      toNum(d[field])?.round() ?? 0;

  /// Total of [field] for completed duties whose date starts with [prefix]:
  /// "2026-10-23" a day, "2026-10" a month, "2026" a year.
  static int total(
      Iterable<Map<String, dynamic>> duties, String field, String prefix) {
    var sum = 0;
    for (final d in duties) {
      if (earned(d) && (d['date'] ?? '').toString().startsWith(prefix)) {
        sum += amount(d, field);
      }
    }
    return sum;
  }

  static int today(Iterable<Map<String, dynamic>> duties, String field, DateTime now) =>
      total(duties, field, dayKey(now));

  static int thisMonth(Iterable<Map<String, dynamic>> duties, String field, DateTime now) =>
      total(duties, field, dayKey(now).substring(0, 7));

  static int thisYear(Iterable<Map<String, dynamic>> duties, String field, DateTime now) =>
      total(duties, field, dayKey(now).substring(0, 4));

  /// The duties physicians worked on [dateKey], earliest shift first.
  static List<Map<String, dynamic>> workedOn(
      Iterable<Map<String, dynamic>> duties, String dateKey) {
    final out = [
      for (final d in duties)
        if (worked(d) && d['date'] == dateKey) d
    ];
    out.sort((a, b) => _ms(a['shiftStart']).compareTo(_ms(b['shiftStart'])));
    return out;
  }

  static int _ms(dynamic v) {
    try {
      return (v as dynamic).millisecondsSinceEpoch as int;
    } catch (_) {
      return DateTime.tryParse('$v')?.millisecondsSinceEpoch ?? 0;
    }
  }

  /// "ICU duty", "Ward duty" or "Specialty duty".
  static String dutyTypeLabel(Map<String, dynamic> d) {
    final type = (d['dutyType'] ?? '').toString();
    const labels = {
      'ward': 'Ward duty',
      'icu': 'ICU duty',
      'specialty': 'Specialty duty',
      'casualty': 'Casualty duty',
      'home': 'Home care visit',
    };
    if (labels.containsKey(type)) return labels[type]!;
    // duties made before the type was saved: the unit says it
    final unit = (d['unit'] ?? '').toString();
    return unit == 'icu' ? 'ICU duty' : unit == 'casualty' ? 'Casualty duty' : 'Ward duty';
  }
}
