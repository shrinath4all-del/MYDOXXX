# MYDOXXX experimental development handover

**Updated: 2 November 2026, India.** Independent backend restoration and guarded Cloud Functions verification are complete. A separate synthetic Firebase test database and 14 role logins are ready, and the Flutter lab builds successfully. **Browser workflow acceptance remains pending at this checkpoint.** A private source-archive backup is now verified on GitHub. These results do not establish production or clinical readiness.

## Use these copies

| Component | Location / identifier | Purpose |
|---|---|---|
| Original IT delivery | `it_team_base/upload-0838449d/received/mydox-master.zip` | Unchanged source archive |
| Protected recovery backend | `mydox-shrinath-backup-261102` | Srinath-owned recovery copy; never the experiment's mutation target |
| **Experimental Firebase project** | **`mydoxxx-dev-261102`**, number **`724915428929`** | New development project, display name **MYDOXXX** |
| Preserved database | `(default)` | 562 restored documents, client access denied |
| **Shared synthetic test database** | **`mydoxxx-testing`**, STANDARD edition, NAM5 | Existing role dashboards share synthetic bookings, status changes and text chat |
| **Flutter source** | **`experiments/MYDOXXX/app`** | Independent application repository |
| **Editable backend source** | **`experiments/MYDOXXX/backend`** | Independent guarded Functions repository |

The Firebase owner is `shrinath4all@gmail.com`. Commands must use the exact project ID above. The existing Antigravity/CliniGo source remains separate. The earlier setup project `mydoxxx` is retired, with billing disabled and zero Auth users; it was not deleted. Do not use it for new work.

## Provenance and Git state

- Received source: remote attachment uploaded on **31 October 2026**, ZIP root `mydox-master/`, 492 extracted files.
- Source ZIP SHA-256: `cf37c4628e2121e216fd9af42ffd885e2fb66021476020fb0c350344ed5b1213`. The received ZIP and original attachment match and remain unchanged.
- Preserved backend snapshot: **2 November 2026, 11:37:31.186 AM IST** (`2026-11-02T06:07:31.186Z`), originally from `mydox-be432`. This is a point-in-time copy; later IT-team changes are not synchronized automatically.
- Both local repositories use branch **`codex/mydoxxx-experiments`**.
- Flutter baseline: `be8a23cbd9179a8c76b6326cb57147054fce78b1`.
- Experimental configuration commit: `6800c876923e5366c216cc3835c88b7dc8f1d45b`.
- Shared role lab and provider inboxes: `5c9ae5076563576842a9ceeeec2f794214c4b7a8`.
- **Latest Flutter commit:** `3c3fe483c744494c2a9512643b040ad1c78b0557` — correct scheduled Doctor testing instructions. This follows directory-loading/error diagnostics at `42b75e36da24ddbd1700c3d7886656b1a91b1c04` and bounded login/concurrent-panel diagnostics at `1bc5474ecdbe0f291d32eff8cf6973e0d09ce144`. The working tree was clean when checked for this update.
- **Backend commit:** `f21181037c1bba645f623af38f34110b438b0125` — editable recovered function source with isolation guards. Its source manifest verifies 40 code files; no clinical records or secret values are included.
- Private GitHub destination: **`shrinath4all-del/MYDOXXX`**. The owner is verified. A source ZIP, README, hash and manifest were uploaded and verified at commit **`78a090f`**. This verifies the source-archive backup checkpoint; it does not claim that the two local repositories have automatic remote synchronization.

## Backend verification

| Component | Verified result | Boundary |
|---|---|---|
| Project | Correct new project and owner; user-approved billing linked | Original IT, CliniGo and protected recovery projects remain excluded |
| Preserved Authentication | **12 original identities unchanged** | Basic Firebase Auth; no real SMS/reset email sent; ten source test-phone bypass settings omitted |
| Synthetic Authentication | **14 test identities; 14/14 sign-ins passed** | Random private credentials; no real names or phone numbers; separate UIDs and server-set claims |
| Preserved Firestore | **562 documents unchanged after test-lab setup** | `(default)` retains the verified deny-all policy |
| Synthetic Firestore | **150 initial seed documents** | New user-created test records may increase the count; no copied clinical data |
| Named-database indexes | **Four unique composite indexes READY** | Read-only check at `2026-11-02T10:42:24.025Z` |
| Access checks | **14/14 test users denied `(default)`; anonymous test-DB access denied** | No Firestore writes during checks; sign-in changes only synthetic login metadata |
| Firebase Rules evaluation | **32/32 remote cases passed** | Exact UID + claim + database isolation; not production role authorization |
| Device tokens | Nine copied FCM entries cleared from 13 fields | Copied device registrations are not reused |
| Storage | **271 files, 132,531,735 bytes** verified; fresh tokens; no public bucket IAM | No backup archives in application bucket; lab uploads disabled |
| File references | **137 links remapped across 64 documents; zero unresolved links** | Verified across all 562 restored documents |
| App registrations | **Six cloud registrations and six local configurations verified** | Native signing, APNs and physical-device testing remain separate |
| Cloud Functions | **36/36 active, with recovery guards, correct project environment and private Cloud Run services** | Node.js 22; minimum instances 0, maximum 1 |
| Function exposure | **13/13 unauthenticated HTTP requests rejected; zero scheduler jobs** | Original callable/scheduled behavior remains inactive |
| Payments | Disabled experimental placeholders only | No live Razorpay secrets or transactions used |

Cloud Functions verification is complete, not pending. `function-cloud-verification.json` records all 36 active handlers and private exposure checks, while explicitly retaining `applicationReady: false` and `activationPending: true`.

## Open the shared role console

On this PC, while its local server runs, open **[http://localhost:8889/](http://localhost:8889/)**. Individual role panels use **localhost ports 8891 through 8904**. Select roles in the console instead of typing credentials.

Available identities: Patient, Doctor, Nurse, Hospital, Ambulance, Technician, Therapist, **three Care Physicians**, and Care Physician, Nurse, Technician and Physio agencies. Each panel has a separate loopback origin and in-memory Firebase Auth session. All share the named synthetic database.

The runtime endpoint supplies only that panel's assigned synthetic credentials. They are not compiled into Flutter assets, placed in URLs or included in Git. The test build verifies project, database, role, UID and signed claims before opening the existing dashboard. Firestore clients are centralized through `AppDatabase`.

**Localhost links work only on the computer running the server.** This console is not a public deployment or mobile download link. Wider access needs a separately reviewed authenticated hosting setup; never expose this credential endpoint to the internet.

## Application validation

| Check | Result |
|---|---|
| Full Flutter suite for role-lab changes | **376 passed, one existing skipped test, zero failures** |
| Static analysis for role-lab changes | Zero errors; two inherited warnings and 66 information notices |
| Role-lab release Web build | Passed; output `experiments/MYDOXXX/app/build/web-lab` |
| Subsequent login/concurrent-panel diagnostic fix | **53 targeted tests passed; release Web rebuild passed**, commit `1bc5474` |
| Directory-loading/error diagnostic fix | **45 targeted tests passed; Web rebuild passed**, commit `42b75e3`; subsequent `3c3fe48` changes testing instructions only |
| Source ZIP integrity and target isolation | Passed |
| Browser role login, booking, acceptance and chat | **Still being verified; not signed off** |
| APK installation or native release/store submission | Not performed in this setup |
| Private GitHub source backup | Source ZIP, README, hash and manifest verified at commit **`78a090f`** |

The later diagnostic fix shows login stages with a 20-second timeout and prevents duplicate-session eviction between synthetic panels. The following directory fix shows hospital-directory loading/errors and synthetic search diagnostics. Their targeted checks and rebuilds passed; a new full 376-test rerun after these small fixes is not claimed. The corrected test guide follows the actual scheduled Doctor choices, Clinic/Visit and Online: clinic bookings auto-confirm, and booked-time OTP/completion opens follow-up chat. Browser verification must still confirm the running build and end-to-end behavior.

Use **Flutter 3.44.1 / Dart 3.12.1** from `C:/Users/Lenovo/Documents/New project/.tools/flutter`; `C:/src/flutter` on PATH is older. This isolated copy pins `pdfrx` to `2.2.24` and has a newly resolved lockfile. Fifteen maintenance tools are quarantined under `disabled-original-tools`; the originals remain in the unchanged received ZIP.

## Actual workflow limits

- **Bookings and text chat:** real shared Firestore records connect existing dashboards. Nurse and Technician have **Patient requests & chats** inboxes alongside their staffing screens. Seeded completed visits unlock the existing 24-hour chat window; they do not prove a freshly booked visit completed successfully.
- **Hospital staffing:** existing client transactions and agency records support synthetic requests and claims. A hospital post accepted through an active care agency now creates its agency duty. Acceptance races, three-person rosters, swaps and agency approvals still need browser walkthrough evidence. The current agency-first offer widens after five minutes to freelancers; it is not a permanent Sai-only restriction.
- **SOS:** the current order is **Patient → Hospital → Doctor → Ambulance**, followed by arrival/OTP stages. Ambulance dispatch is not before doctor assignment. GPS uses synthetic Wakad coordinates; real routing and dispatch are unverified.
- **Ranking:** existing IT-source ordering uses no-shows ascending, experience years descending, then application time ascending. This work does not implement or verify the proposed complete **Professional Efficiency Score**.
- **Notifications:** foreground request listeners and derived in-app events can update live. Guarded recovered Functions do not operate on the named database. Background FCM, saved server inbox notifications, scheduled expiry and server business enforcement are not demonstrated here.
- **Payments:** a lab-only action marks the current patient's accepted synthetic appointment as a test payment to exercise the next UI step. It does not charge, settle, change wallets, create commissions, refund or pay providers. Razorpay TEST integration, idempotency and webhooks remain separate work.
- **External services:** real SMS, push registration, uploads, real GPS, external links and camera/audio/video calls remain disabled. Enter only fictional test information.
- **Authorization:** exact synthetic identities and server claims restrict this cooperative sandbox. They may work across synthetic records. These rules do not prove production ownership, clinical privacy, state-transition enforcement or pricing integrity.
- **Native platforms:** Android/iOS releases, signing and store acceptance remain unverified. A separate experimental package/bundle is needed for side-by-side installation because the configured `com.mydox.app` can replace the original. Desktop source remains under `desktop-platforms-held` and is not claimed supported.

## Next steps

1. Complete browser tests: simultaneous roles, fresh bookings, acceptance, text chat, hospital staffing, competing claims and the four-panel SOS sequence. Record actual results and failures.
2. Verify the local console serves the latest diagnostic build and capture final UI evidence.
3. Refresh and verify the private `shrinath4all-del/MYDOXXX` source archive after final UI fixes, retaining the verified `78a090f` backup checkpoint and excluding private exports, passwords, build output, signing material and real records.
4. Design and test production role/ownership rules and server-side enforcement separately from this synthetic collaboration policy.
5. Restore callable protocols, schedules and external services only through deliberate changes with synthetic acceptance tests; do not simply turn recovery mode off.
6. Test Razorpay TEST mode, device notifications and OTP independently before native release or wider hosting.

## Evidence

- [Role-lab guide](../../experiments/MYDOXXX/app/MYDOXXX-TEST-LAB.md)
- [Role-lab validation](../../experiments/MYDOXXX/app/MYDOXXX-TEST-LAB-VALIDATION.json)
- [Application guide](../../experiments/MYDOXXX/app/MYDOXXX-README.md)
- [Backend source guide](../../experiments/MYDOXXX/backend/README.md)
- [Backend code validation](../../experiments/MYDOXXX/backend/VALIDATION.json)
- [Original ZIP provenance](../../experiments/MYDOXXX/app/MYDOXXX-SOURCE.json)
- [Test-backend setup and verification guide](../../scripts/mydoxxx/TEST-LAB.md)

The older `MYDOXXX-VALIDATION.json` describes the earlier 323-test checkpoint. Use the role-lab receipt and later diagnostic test/build logs for current changes; do not add their test totals together.

Private evidence under `private-backups/mydoxxx-dev-261102` includes `data-final-verification.json`, `function-cloud-verification.json`, `test-lab-verification.json`, `test-lab-access-check.json`, `test-lab-rule-test.json`, `test-lab-index-verification.json` and restore receipts. The seed plan again exactly matches its saved checksum: optional late schema suggestions were reverted locally; no cloud overwrite or migration occurred. See `test-lab-late-fixture-audit.json`.

Do not publish the private backup directory or its credentials/exports. The protected recovery handover remains in `docs/backend-recovery-2026-11-02/STATUS.md`.
