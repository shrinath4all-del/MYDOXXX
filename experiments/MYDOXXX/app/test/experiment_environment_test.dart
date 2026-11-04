import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/config/experiment_environment.dart';

void main() {
  test('Experimental build blocks external side effects by default', () {
    expect(ExperimentEnvironment.externalActionsEnabled, isFalse);
    expect(ExperimentEnvironment.requireExternalActions, throwsStateError);
  });
  test('MYDOXXX startup accepts only its own project', () {
    expect(() => ExperimentEnvironment.validateProject('mydoxxx-dev-261102'),
        returnsNormally);
  });
  for (final project in [
    'mydoxxx',
    'mydox-be432',
    'clinigo-77808',
    'mydox-shrinath-backup-261102',
    ''
  ]) {
    test('MYDOXXX startup rejects preserved or missing project: $project', () {
      expect(() => ExperimentEnvironment.validateProject(project),
          throwsStateError);
    });
  }
}
