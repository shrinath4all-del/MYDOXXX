/// Prevents this experimental app from ever starting against a preserved backend.
class ExperimentEnvironment {
  static const projectId = 'mydoxxx-dev-261102';
  // Enable only after synthetic-account and external-service review.
  static const externalActionsEnabled = false;

  static void requireExternalActions() {
    if (!externalActionsEnabled) {
      throw StateError(
          'MYDOXXX experiment: live SMS, push and payments are disabled.');
    }
  }

  static void validateProject(String actualProjectId) {
    if (actualProjectId != projectId) {
      throw StateError(
        'MYDOXXX is isolated. Expected Firebase project $projectId, '
        'but received $actualProjectId. Check the experiment configuration.',
      );
    }
  }
}
