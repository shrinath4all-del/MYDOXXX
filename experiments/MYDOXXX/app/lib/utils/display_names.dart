/// Names as people read them.
class DisplayNames {
  DisplayNames._();

  static final RegExp _drPrefix = RegExp(r'^\s*dr\.?\s+', caseSensitive: false);

  /// "Dr. Kunal Jadhav" whether the saved name is "Kunal Jadhav",
  /// "Dr Kunal Jadhav" or "Dr. Kunal Jadhav" (never "Dr. Dr …").
  static String doctor(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'Doctor';
    return 'Dr. ${n.replaceFirst(_drPrefix, '').trim()}';
  }

  /// "1 doctor", "3 doctors".
  static String count(int n, String singular, [String? plural]) =>
      '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';
}
