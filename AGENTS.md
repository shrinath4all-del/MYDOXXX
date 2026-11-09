# MYDOXXX shared source: instructions for both laptops

This is the prepared independent MYDOXXX source tree, not the original Antigravity
CliniGo checkout. It must not change the current PC's canonical workspace merely
by being prepared or published. Work only in the user-selected clone of this root.

- One Git root contains `experiments/MYDOXXX/app` and `experiments/MYDOXXX/backend`.
  Do not run `git init` in those subfolders, create nested repos/submodules, or
  overwrite the app with a historical ZIP. Preserve local/concurrent edits.
- Project: `mydoxxx-dev-261102`, number `724915428929`; synthetic named database:
  `mydoxxx-testing`. Do not modify its preserved `(default)` database or the
  protected projects `mydox-be432`, `mydox-shrinath-backup-261102`, `clinigo-77808`,
  or retired `mydoxxx`.
- Read SHARED-DEVELOPMENT.md, CLOUD-TEST-ROOM-HANDOFF.md and
  scripts/mydoxxx/cloud-test-room/CI-SETUP.md. Run `scripts/mydoxxx/dev-status.py` before edits.
  Inspect Git status. Update only a clean branch using `git pull --ff-only`.
  Use a unique branch per task/laptop; coordinate overlapping files. Never reset,
  clean, force-push, discard edits or auto-stash to resolve a divergence.
- Building/running the local test room does not authorize seeding, data migration,
  Auth reset/provider changes, rules/indexes/functions deployment, billing changes,
  or external SMS/payment/notification activation. Old recovery scripts are
  reference-only unless a separately reviewed task explicitly requires them.
- Existing test credentials are transferred privately to ignored
  `private-backups/mydoxxx-dev-261102/test-lab-credentials.json`. Never print them,
  commit/upload them, place them in build assets, or serve the whole file. Never
  copy a portable runtime ZIP into Git; it contains the 36 test passwords.
- Build the local lab with compile-time `MYDOXXX_TEST_LAB=true`. Its password-based
  Python host and separate account ports must remain loopback-only. The separate
  owner-authenticated cloud build uses the reviewed flags and HTTPS origin in the
  cloud handoff. Service OTP7777 is a test booking/
  duty code, not SMS login. Do not weaken existing validators or app guards.
- Public Firebase SDK configuration identifies the experiment; it is not an Admin
  credential. Do not add private credentials to solve missing local authentication.
- No auto-install, auto-fetch/push, deployment or repository migration is performed
  by dev-status. GitHub plugin access and local Git authentication are separate.
  If Git CLI lacks access, use the approved connector for scoped branch/PR work,
  or ask the owner to configure local access. Never extract/store connector tokens.
- Reviewed main merges automatically deploy the static cloud test room after
  checks pass. This does not authorize backend/Firebase changes. Backend source
  retains recovery guards, private HTTP
  handlers and deny-all default recovery rules. Do not claim this synthetic lab
  validates production privacy, medical readiness, real payments or background push.
