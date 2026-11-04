# MYDOXXX — Claude Code project instructions

Read root `AGENTS.md`, `SHARED-DEVELOPMENT.md`, `CODEX-HANDOFF.md` and
`CLAUDE-HANDOFF.md` before changing code. These instructions apply to the private
`shrinath4all-del/MYDOXXX` shared repository. Preserve other agents' work.

- Use **one Git root**. Flutter source is `experiments/MYDOXXX/app`; backend source
  is `experiments/MYDOXXX/backend`; local viewer/helpers are `scripts/mydoxxx`.
  Do not initialize nested repos, replace the app from an archive, rewrite it in a
  different framework, or switch the backend to Supabase.
- Keep the existing Claude task branch and its commits. Verify the current branch,
  status, remote and history, then follow the safe integration steps in the handoff.
  Merge the verified latest `origin/main` into the task branch; do not force-push,
  reset, clean, auto-stash, silently rebase or discard local/remote edits. Do not
  resolve conflicts by taking an entire side without reviewing the actual change.
- Only project `mydoxxx-dev-261102` (number `724915428929`) and the existing synthetic
  named database `mydoxxx-testing` belong to this test app. Do not modify the
  preserved `(default)` database, CliniGo, original IT or recovery projects.
- There are **36 existing synthetic identities: three per 12 role families**.
  Cardiologist1–3 retain `doctor`, `doctor_2`, `doctor_3` keys and their existing
  UIDs. Do not create replacements or change identity/port mappings for convenience.
- Public Firebase SDK configuration is already source-controlled. Private test
  passwords are not in GitHub. Missing credentials or blocked cloud access does
  not authorize seed/reset scripts, Auth changes, dummy sign-in bypasses, security
  rule changes, service-account creation, or copying passwords into app assets.
- Coding/building does not authorize Firebase deployment, migration, billing,
  security changes, or activation of real payments, SMS, notifications or medical
  dispatch. Recovered backend functions remain guarded and do not process the
  named synthetic database. Legacy recovery scripts are reference-only.
- Source verification used Flutter3.44.1/Dart3.12.1; use the lockfile and compatible
  existing tools. Do not automatically install or upgrade dependencies/SDKs.
  Build the lab with `--dart-define=MYDOXXX_TEST_LAB=true`. Service OTP7777 is only
  a booking/duty test code; keep validators and real sign-in flows unchanged.
- A cloud development environment's localhost is not the user's laptop. Keep the
  credential-bearing multi-role server loopback-only. Do not publish it through a
  preview URL, tunnel, public host or permissive CORS to make a demo accessible.
- Use a unique task branch, small commits and a PR to main. Review intended files
  before staging. Report commit, changed paths, tests actually run, remaining
  limitations and any overlapping work needing coordination. Never claim passing
  runtime/Firestore tests when SDKs, credentials or network were unavailable.

`python scripts/mydoxxx/dev-status.py` checks local Git/version and public target
configuration only. It does not fetch, deploy or connect to Firebase. Source sync,
compiled app refresh and shared database activity are separate operations.
