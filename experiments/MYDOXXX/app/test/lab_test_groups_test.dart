import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/lab_test_groups.dart';

void main() {
  test('tests are shown as Neuro, Blood, then Other tests', () {
    final groups = LabTestGroups.group([
      {'name': 'ECG', 'category': 'other'},
      {'name': 'CBC (Complete Blood Count)', 'category': 'blood'},
      {'name': 'EEG', 'category': 'neuro'},
      {'name': 'Old test'}, // no category: other
    ]);
    expect(groups.map((g) => LabTestGroups.patientLabels[g.$1]),
        ['Neuro tests', 'Blood tests', 'Other tests']);
    expect(groups.last.$2.map((t) => t['name']), ['ECG', 'Old test']);
  });

  test('unknown categories count as other tests', () {
    expect(LabTestGroups.of({'category': 'NEURO'}), LabTestGroups.neuro);
    expect(LabTestGroups.of({'category': 'cardio'}), LabTestGroups.other);
  });
}
