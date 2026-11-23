# MyDox private cloud test room — Claude / Codex handoff

Base site status date: **5 November 2026**; cloud-data workflow added **23 November 2026**.
This handoff describes the separate shared
synthetic testing environment, not a production clinical launch.

## Shared source and safe integration

The cloud source and approved build pipeline are on **main** in the private
`shrinath4all-del/MYDOXXX` repository. For a new Codex or Claude task, inspect local
changes, update a clean main with `git pull --ff-only`, then create a unique task
branch. Preserve existing work and coordinate overlapping files. Do not force-push,
reset another agent's work or replace current source with an older archive.

Use a PR into main, pass **Cloud lab checks**, and obtain review. A reviewed main
merge automatically publishes the static cloud test room after Netlify checks
pass; merging is therefore a deployment action. Firebase/Auth/rules/functions,
IAM and billing remain separately authorized operations. See
[scripts/mydoxxx/cloud-test-room/CI-SETUP.md](scripts/mydoxxx/cloud-test-room/CI-SETUP.md).
Preserve the 36-role testing room, Cardiologist identities, responsive emergency
dialogs, panel presentation controls and compile-time service OTP `7777`.

Claude now has separate timezone **PR #1**, branch `claude/roster-timezone-fix`,
verified head `29732384524de27ac74aeea0c59e734210e9016d`. Keep that PR separate;
this cloud-source publication does not merge it.

Claude's earlier commit `9f5d0a9b207ca0617433b3db50cd65a58276344f` imported an older
snapshot. Preserve the useful India-wall-clock timezone correction by comparing
and applying only its narrow changes if they are not already present:

- `experiments/MYDOXXX/app/lib/models/care_duty_roster.dart`
- `experiments/MYDOXXX/app/lib/services/care_physician_service.dart`
- `experiments/MYDOXXX/app/lib/services/care_duty_service.dart`
- `experiments/MYDOXXX/app/lib/services/nurse_duty_service.dart`
- `experiments/MYDOXXX/app/lib/services/technician_duty_service.dart`

Do not replace current source with that older import. Keep the newer `ServiceOtp`
integration when reconciling `care_physician_service.dart`. Add dedicated timezone
tests and run them in UTC and Asia/Kolkata; the older 376-test claim does not
validate the current cloud build.

## Database changes without the original PC

Use the separately authorized [cloud-data workflow](scripts/mydoxxx/cloud-data/README.md)
for owner-approved synthetic catalogue changes. The owner opens **MYDOXXX cloud
database** in GitHub Actions, chooses `main`, runs **preview**, reviews the exact
plan, then starts **apply** with that preview run ID and plan hash. **Verify** is
read-only. The workflow uses a GitHub-hosted runner and temporary Google Workload
Identity Federation access; the owner's PC can be switched off.

This is separate from Netlify publishing and from a Claude Local session. Claude
or Codex can prepare reviewed code and data-operation PRs using GitHub access;
the cloud chat is not given a Firebase owner login or reusable database key.
The initial loader is restricted to the 21-test `lab_tests` catalogue. Future
operations require a reviewed allowlisted loader and tests; do not run arbitrary
maintenance scripts or the IT team's default-database seeder.

Google trust is restricted to this repository's immutable ID, the owner's numeric
actor ID, this exact main-branch workflow, a first-attempt manual dispatch and a
GitHub-hosted runner. IAM is conditioned on `mydoxxx-testing`, with document
read/create/update but no delete or administration. The loader uses Firestore
REST and additionally limits writes to the catalogue. It verifies that the
protected `(default)` database returns permission denied. The existing local
recovery helpers and owner checks remain unchanged.

The owner elected to proceed without a paid plan upgrade or branch protection.
The separate apply request records approval of a preview but does not make the
workflow immutable. Main-branch edits remain the owner's responsibility. Use a
new **Run workflow** request for retries; **Re-run jobs** is intentionally rejected.
No successful live run should be claimed without its GitHub run/report evidence.

## Hosted access

Site: **https://mydoxxx-live-test.netlify.app/**

The deployment is **private and Netlify-team protected**, with two access layers:

1. Netlify site access requires membership/access in the `kunal110284` Netlify
   team. Receiving the URL or using the app's Google account does not grant this.
2. Inside the portal, Google sign-in is restricted to **shrinath4all@gmail.com**.
   Then the operator can open the 36 synthetic role identities.

Do not share passwords to solve either access layer. The site and Firebase can
run without the original PC. These files contain source and public Firebase web
configuration only, not any reusable local test password or owner credential.

## Target and protections

- Project: `mydoxxx-dev-261102` (MYDOXXX), project number `724915428929`.
- Named **Standard** Firestore database: `mydoxxx-testing`.
- The restored `(default)` database remains denied to these clients.
- CliniGo, the original IT backend and the protected Srinath recovery copy are
  outside this cloud work. Do not retarget or deploy into them.
- The 36 identities share one cooperative synthetic database. Each may read and
  write the test data; this is not production role-level patient authorization.
- The existing local test room and its private runtime credentials remain separate.

## Source map

| Path | Purpose |
|---|---|
| `experiments/MYDOXXX/app/` | Flutter app, cloud-only login guard, custom-token exchange and tests |
| `experiments/MYDOXXX/app/MYDOXXX-CLOUD-TEST-LAB.md` | Build flags, panel bridge contract and verification limits |
| `scripts/mydoxxx/cloud-test-room/` | Owner portal, per-frame bridge, catalogue/bridge tests and static packager |
| `scripts/mydoxxx/test-console-state.js` | Explicit local versus approved-cloud catalogue validation |
| `scripts/mydoxxx/test-console.html` and `test-console.js` | Existing shared presentation shell; already on the reviewed base |
| `experiments/MYDOXXX/cloud-test-room-broker/` | Separate owner-gated role-token function, policy, tests and reviewed setup helpers |
| `experiments/MYDOXXX/cloud-test-room-rules/` | Exact 36-role policy with cloud-session expiry and remote mock-test runner |

The named owner Firebase app keeps the operator session separate from each
Flutter frame's default app and in-memory role login. The broker verifies the
current Google owner and mints only fixed existing synthetic identities.
PostMessage checks origin, requesting window, role and request ID. Owner ID tokens
and custom tokens must never enter URLs, logs, source files or browser storage.

## Deployment state and test evidence

Native automatic publishing was verified on 5 November 2026: Netlify deployment
`6aec447735617a4fec132438` published main commit
`d585896db57de2178de04821689c00cb97514afe`. The GitHub trigger and published pointer
were checked. This source commit is a verification checkpoint, not a permanent pin.

Configured/deployed at this checkpoint: the team-protected Netlify site, Google
provider and approved Netlify auth domain, dedicated token-broker runtime
identity/permissions, the separate broker function, and named-database cloud
expiry policy. Do not automatically rerun setup because source was downloaded.

- Flutter focused login/isolation tests: **156 passed in each** normal, local-lab
  and cloud-lab mode; targeted analysis and the cloud release build passed.
- Rules source: **163 mocked Rules API cases passed**, covering all local users,
  valid and expired cloud sessions, invalid claims and default-database denial.
- Broker: **17 offline tests passed**. Live negative/preflight checks passed for
  missing/wrong Origin, missing authentication, malformed role and allowed CORS.
- Positive Google operator login through the hosted browser UI, real role-token
  exchange/refresh, simultaneous cloud panels and logout cleanup are **not yet
  confirmed**. The full hosted workflow must not be marked complete until tested.

Test the real sign-in and confirm the resulting Firebase ID token retains the
signed cloud expiry claims after refresh. Then prove separate role identities,
one booking, two-way chat, and sign-out clearing all current panels. Record only
sanitized results, never token contents.

## Expiry and remaining limitations

The broker signs `cloudLab: true`, `labIssuedAt`, and `labExpiresAt` in epoch
milliseconds. Named-database rules require integer times, an issued time not in
the future, an expiry after request time, and a lifetime no longer than eight
hours. Refreshing an ID token does not extend that absolute window.

Removing broker access blocks new grants, but an already issued cloud role
session can remain valid until its signed expiry. Immediate per-operator server
revocation is not implemented. Revoking a shared role UID affects other laptops
using that same synthetic identity. Local tokens without `cloudLab` retain the
existing loopback testing policy.

Real SMS, payments, clinical dispatch, push, media calls, uploads and live GPS
remain disabled. Foreground testing is not proof of background workflow readiness.

## Reproducing safely

The cloud release requires the three reviewed defines in the Flutter handoff and
`--base-href=/panel/`. Its hostname is deliberately fixed; deploy previews or a
different domain require a reviewed configuration change.

`package-site.py` requires a separately built `app/build/web-cloud-lab`. Local
packaging retains its private 36-password scan input. CI uses `--ci --output
dist/cloud-test-room`, a strict file allowlist, private-key/token checks, and
SHA-256 fingerprints of the 36 high-entropy generated test passwords. It does
not need or read the private credential file. Never upload that file or reusable
credentials to GitHub or Netlify. Password rotation requires a deliberate
fingerprint refresh. See `scripts/mydoxxx/cloud-test-room/CI-SETUP.md` for the
approved-main pipeline and its current integration status. Build outputs and
private deployment receipts remain excluded from the repository.

The included `setup-google.cjs`, `deploy-rules.cjs`, broker `setup-iam.cjs` and
IAM role definitions are reviewed deployment source, **not automatic tasks**.
They require separately authorized target-checked operations. Some rely on the
original workspace's guarded `common.cjs`, local Firebase CLI installation and
private verification receipts; they are not universal setup commands for every
laptop. Do not run recovery, seed or maintenance scripts just to open the app.

Use the broker's offline tests and frontend catalogue/bridge tests without cloud
credentials. The rules `--remote` runner evaluates mocked source without deploying
it; live testing still requires the separately approved owner session.
