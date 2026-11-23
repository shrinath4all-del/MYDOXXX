# Cloud database updates from any laptop

This is the owner-requested, manual database path for the private
`shrinath4all-del/MYDOXXX` repository. It uses GitHub-hosted runners and temporary
Google Workload Identity Federation access. The original PC can be switched off.
Claude and Codex can prepare changes through their existing GitHub connection;
neither needs the owner's local Firebase login or a permanent database key.

## What it can change

- Project: **mydoxxx-dev-261102**, project number **724915428929**.
- Database: **mydoxxx-testing**, Standard edition, synthetic testing only.
- The first operation supports **lab_tests** catalogue additions and metadata
  completion. It preserves prices already set and never deletes documents.
- It uses the same 21-test plan as the existing local helper. Adding future data
  operations requires a reviewed code change with tests and an explicit operation
  in the workflow. It does not run arbitrary uploaded scripts or SQL.
- It cannot administer Firebase Auth, rules, Storage, functions or billing. The
  protected `(default)` database and other Firebase projects are outside its IAM
  grant. The verification operation checks default-database denial through REST.

Google's IAM grant is scoped to the **whole named test database**, with only the
document-read/create/update permissions needed by the loader. The loader further
limits its writes to `lab_tests`. Firestore server REST access uses IAM, not client
Firestore Security Rules; this is not production patient-data authorization.

## Everyday use

1. Claude or Codex prepares and tests the change on a task branch. Review and
   merge the PR into `main`. A merge continues to publish the website through
   Netlify; it does **not** run a database update.
2. Sign into GitHub as **shrinath4all-del**. Open
   [MYDOXXX cloud database](https://github.com/shrinath4all-del/MYDOXXX/actions/workflows/mydoxxx-data.yml).
   Click **Run workflow**, choose **main**, choose **preview**, and run it.
   Leave the price input empty to preserve existing prices and leave missing ones
   unset. Enter a whole-rupee amount only when intentionally setting a default for
   tests that do not yet have a price.
3. Open the completed run and read its summary. It lists additions and updates,
   the source commit, the preview run ID and the **plan SHA-256**. The preview only
   reads the database. Its `mydoxxx-data-preview` artifact contains `plan.json`.
4. If the preview is correct, use **Run workflow** again on **main**, select
   **apply**, and enter that preview's run ID and exact 64-character plan hash.
   Leave the price input empty for apply. This separate, explicit request is your
   approval of that particular preview. No additional owner-PC step is required.
5. Read the result and the sanitized `mydoxxx-data-report` artifact. The helper
   checks the live data again, uses atomic write preconditions, then verifies the
   result. If the commit, relevant data, artifact or approved plan changed, apply
   stops and requires a fresh preview. Plans expire after 24 hours.

Use **verify** to read the current catalogue and check database isolation without
writing. For a retry, start a **new Run workflow** request. The **Re-run jobs**
button is intentionally unsupported: Google only trusts the first attempt of an
owner-triggered dispatch. A new commit also requires a new preview.

The first catalogue was already loaded on 23 November 2026. An unchanged preview
should therefore report **zero changes**. Do not expect to add the same tests again.

## What protects the connection

- Google trust checks the immutable repository ID **1442833578**, owner/actor ID
  **281172251**, exact repository and workflow, `main`, manual-dispatch event,
  first run attempt and GitHub-hosted runner.
- The workflow also rejects a different actor or rerun. Pull requests only run
  offline safeguard tests with no OIDC grant and no database connection.
- Apply checks the successful owner-requested preview run, same repository,
  workflow, main commit and attempt before downloading its artifact. The loader
  validates the plan hash, target, expiry and current data before any write.
- Google access is short-lived and exchanged in memory by `run.cjs`. No service
  account key, owner password, local Firebase token or credential JSON belongs in
  GitHub secrets, artifacts, logs or app assets. Temporary credentials are never
  part of the preview/report artifacts.
- Operations against this one database are serialized. A later run does not
  cancel an in-progress write.

At the owner's request, this setup does **not** require a GitHub plan upgrade,
protected branch or paid environment reviewer. The owner controls repository
changes. A manual apply run is an operational approval step, not an immutable
review barrier: someone with permission to change trusted `main` code and invoke
an owner-authorized run could change its behaviour within the Google IAM grant.
Do not describe this as protected-branch enforcement.

## Source map

| File | Purpose |
|---|---|
| `.github/workflows/mydoxxx-data.yml` | Owner-only manual preview/apply/verify job |
| `.github/workflows/mydoxxx-data-checks.yml` | Offline PR/main checks; no Google login |
| `run.cjs` | Temporary Google access and scoped operation entry point |
| `catalogue.cjs` | Plan, compare, atomic apply and read-back verification |
| `validate-preview.cjs` | Same-repo, owner/main/commit/run provenance checks |
| `*.test.cjs` | Offline safeguards and regression tests |

Run offline checks with Node 22 from the repository root:

```text
node --test scripts/mydoxxx/cloud-data/*.test.cjs scripts/mydoxxx/test-lab-lab-tests.test.cjs
```

The original `test-lab-lab-tests.cjs` and guarded local recovery helpers remain
available on the owner's PC. Their Windows paths and owner checks have not been
weakened to make cloud access work.

## Google setup and limits

The separate setup provisions the pool `mydoxxx-github-data` and provider `github`
under project number 724915428929, a minimal custom role and a database-conditioned
IAM binding. The workflow uses direct federation; no service account key is
created. Setup is a one-time owner-authorized infrastructure action, not a step
run by each workflow. It does not upgrade billing or change the Netlify access gate.

GitHub-hosted runner usage and Firestore requests use the accounts' existing quotas
and billing arrangements. This design does not promise unlimited free execution.
The synthetic test room remains separate from a production clinical system.

References: [Google deployment-pipeline federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines),
[Firestore database IAM conditions](https://firebase.google.com/docs/firestore/manage-databases),
[GitHub workflow dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
