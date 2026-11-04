<!-- Shared import: root AGENTS.md governs Git/deployment workflow. -->
# MYDOXXX experimental app â€” explicit source override

The user approved this independent experimental copy on 2 November 2026.
For tasks about MYDOXXX experiments, this directory is the working source.
The parent AGENTS.md canonical CliniGo path applies to the shared original app,
not this explicitly requested new copy. Never edit or deploy into CliniGo,
mydox-be432, or mydox-shrinath-backup-261102 from this experiment.

- Firebase project: `mydoxxx-dev-261102` (display name MYDOXXX), owner shrinath4all@gmail.com.
- Always supply --project mydoxxx-dev-261102 --account shrinath4all@gmail.com to Firebase CLI.
- Original IT ZIP remains unchanged; SHA and source path are in MYDOXXX-SOURCE.json.
- This app has a startup project guard. Do not bypass it to use an old backend.
- disabled-original-tools contains quarantined old-target scripts for reference.
  Do not restore or run them until project targets and effects are reviewed.
- Original functions/functions_push sources are preserved, but are not deployable
  through this app firebase.json. Cloud experimental function deployment is a
  separate guarded recovery operation; no live Razorpay payments or scheduled
  jobs are authorized by a UI-only change.
- Do not add dummy authentication over copied personal data. The user explicitly
  authorized the local multi-role test lab on 2 November 2026. Its compile-time
  MYDOXXX_TEST_LAB build may initialize the MYDOXXX Firebase app only with
  synthetic Auth identities and named Firestore database mydoxxx-testing.
  The default restored database stays denied. Runtime credentials come only
  from role-specific loopback servers, never public assets or Git.
- Shared-source publication is handled separately by the owner. Use the single
  root Git workflow in SHARED-DEVELOPMENT.md; never initialize Git here. Keep record
  exports, signing keys, server credentials and logs out of Git.
