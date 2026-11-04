# MYDOXXX experimental backend

This is the clean, editable backend source for **MYDOXXX**. Its only deployment
target is **`mydoxxx-dev-261102`**, project number **`724915428929`**, under
`shrinath4all@gmail.com`. The Flutter app is in the separate sibling `../app` folder.

## What is included

- Three Cloud Functions source groups containing the 36 recovered handlers.
- The original business implementations, package manifests and lockfiles.
- MYDOXXX project guards and a safe environment file containing only
  `MYDOX_RECOVERY_MODE=true`.
- Firebase configuration, the copied composite index and closed recovery rules.
- Local isolation checks, guard tests and a deployment helper with a fixed target.

The code-only `SOURCE-MANIFEST.json` records SHA-256 parity for all 40 files copied
from the private staging packages. It contains no user records or secret values.
The unused original image-upload maintenance script was omitted because it points
to a protected old bucket. The original ZIP and protected Firebase recovery copy
remain available separately.

## Start development

1. Use Node.js **22**. Install dependencies in each function group:

   ```powershell
   npm --prefix functions/group-48df0170 ci --ignore-scripts --no-audit --no-fund
   npm --prefix functions/group-bb9ed54e ci --ignore-scripts --no-audit --no-fund
   npm --prefix functions/group-7dd56ad3 ci --ignore-scripts --no-audit --no-fund
   ```

2. Run the local checks:

   ```powershell
   npm run verify
   npm run test:guards
   npm run test:source
   ```

3. Use `npm run verify:baseline` only when checking the untouched initial copy.
   Subsequent intentional source edits will differ from the baseline hashes.

4. Keep experimental changes in this repository on branch
   `codex/mydoxxx-experiments`. No remote or public publication is configured.

## Deploy this experimental project's guarded functions

The helper validates locally by default. After installing dependencies and signing
into the Firebase CLI as Srinath, use:

```powershell
./scripts/deploy.ps1
./scripts/deploy.ps1 -Deploy
```

The helper specifies the project and account explicitly and deploys only functions.
It does not change the Flutter app, another backend, database records, billing or
client rules. The deployment can create/update this experiment's cloud functions
and their supporting Google resources. Firebase billing must already be configured.

## Current activation state

Recovery guards are enabled. Twenty-three event handlers are inert; 13 endpoints
are private HTTP staging endpoints. Original scheduled/callable definitions remain
in the business source but are not currently exposed in their live form. The client
Firestore and Storage rules deny access. This preserves a recoverable baseline; it
does not prove that app workflows, payments or notifications are live.

Three Secret Manager names are expected in the experimental project:
`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`. They initially
contain disabled placeholders. Secret values do not belong in this repository.

Before activating workflows, use synthetic test identities and devices, valid
Razorpay **TEST** credentials, reviewed authorization rules, deliberate callable and
scheduler restoration, and multi-role tests. Do not simply switch recovery mode off
or reuse the protected source project's live credentials/device tokens.

Known dependency warnings are preserved from the original locked package versions;
review upgrades as a separate change. The code-copy checks are not a full security
audit or clinical/regulatory compliance certification.
