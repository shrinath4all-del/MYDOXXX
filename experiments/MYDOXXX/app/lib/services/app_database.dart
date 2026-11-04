import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../config/experiment_environment.dart';
import '../config/test_lab_config.dart';

/// Every app database access goes through this boundary. The test build never
/// obtains the default database that holds the preserved recovery records.
class AppDatabase {
  static FirebaseFirestore get instance {
    final app = Firebase.app();
    ExperimentEnvironment.validateProject(app.options.projectId);
    return FirebaseFirestore.instanceFor(
      app: app,
      databaseId:
          TestLabConfig.enabled ? TestLabConfig.databaseId : '(default)',
    );
  }
}
