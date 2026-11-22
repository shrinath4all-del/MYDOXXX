/// The groups lab tests are shown in (`lab_tests/{name}.category`, see
/// firestore_seed/set_lab_tests.js). A test with no or an unknown category
/// is an "other" test.
class LabTestGroups {
  LabTestGroups._();

  static const String neuro = 'neuro';
  static const String blood = 'blood';
  static const String other = 'other';

  /// Display order of the groups.
  static const List<String> order = [neuro, blood, other];

  /// Headings for patients booking a test.
  static const Map<String, String> patientLabels = {
    neuro: 'Neuro tests',
    blood: 'Blood tests',
    other: 'Other tests',
  };

  /// Headings for technicians (and hospitals asking for them): a neuro
  /// technician does all the neuro tests.
  static const Map<String, String> technicianLabels = {
    neuro: 'Neuro technician',
    blood: 'Blood tests',
    other: 'Other tests',
  };

  /// The group key of a test (`category`), "other" when unknown.
  static String of(Map<String, dynamic> test) {
    final c = (test['category'] ?? '').toString().trim().toLowerCase();
    return order.contains(c) ? c : other;
  }

  /// [tests] split into groups, in display order; empty groups left out.
  /// Tests keep their order inside a group.
  static List<(String, List<Map<String, dynamic>>)> group(
      List<Map<String, dynamic>> tests) {
    return [
      for (final g in order)
        (g, [for (final t in tests) if (of(t) == g) t]),
    ].where((e) => e.$2.isNotEmpty).toList();
  }
}
