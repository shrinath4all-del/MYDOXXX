# MYDOXXX experimental development handover

**Updated: 3 November 2026, India.** Independent backend restoration and guarded Cloud Functions verification are complete. The synthetic Firebase lab now has **36 role identities (three in each of 12 families)**, with additive migration and access checks verified. The Flutter lab builds successfully; the new account picker and live browser pass are tracked separately. **Browser smoke checks confirmed a new Patient booking appeared in the Doctor dashboard, the scheduled-time OTP restriction worked, and Patient/Doctor text chat worked in both directions.** Full all-role and end-to-end workflow acceptance remains pending. The previous private source-archive backup is verified on GitHub; the new 36-account source snapshot is local until separately uploaded. These results do not establish production or clinical readiness.

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
- **Latest Flutter commit:** `57379575165107f3fe93228ce7a53287df445627` — shared service-code generation with 7777 restricted to the compile-time lab; normal random generation and stored-code validators retained. It follows responsive dialogs `b403f99`, Cardiologist work `7ac8a64`, Nurse presentation `7b5fcc3` and 36-account implementation `2075c24`. Auth is unchanged; the existing-record OTP migration is separate and narrowly scoped below. The working tree was clean when checked for this update.
- **Backend commit:** `f21181037c1bba645f623af38f34110b438b0125` — editable recovered function source with isolation guards. Its source manifest verifies 40 code files; no clinical records or secret values are included.
- Private GitHub destination: **`shrinath4all-del/MYDOXXX`**. The owner is verified. The final **112503Z source ZIP**, manifest, SHA-256 file and updated README were uploaded and verified at commit **`ded30c912337fdb312404d72830f3d1585b01990`**. This archive includes Flutter fixes `42b75e3` and `3c3fe48`. Earlier commit `78a090f` remains the verified baseline. These are source-archive backup checkpoints; the two local repositories do not automatically synchronize to GitHub. The subsequent browser observations below are local handover additions and were not repackaged into that archive.

## Backend verification

| Component | Verified result | Boundary |
|---|---|---|
| Project | Correct new project and owner; user-approved billing linked | Original IT, CliniGo and protected recovery projects remain excluded |
| Preserved Authentication | **12 original identities unchanged** | Basic Firebase Auth; no real SMS/reset email sent; ten source test-phone bypass settings omitted |
| Synthetic Authentication | **36 test identities; 36/36 sign-ins passed** | Random private credentials; no real names or phone numbers; separate UIDs and server-set claims |
| Preserved Firestore | **562 documents unchanged after the 36-account expansion** | `(default)` retains the verified deny-all policy |
| Synthetic Firestore | **333 expected fixture documents present; 337 total at migration verification** | 183 additive fixtures; all 154 pre-existing named records preserved; later test activity may change totals |
| Named-database indexes | **Four unique composite indexes READY** | Read-only check at `2026-11-02T10:42:24.025Z` |
| Access checks | **36/36 test users denied `(default)`; anonymous test-DB access denied** | Verified `2026-11-03T05:53:11.518Z`; no Firestore writes; synthetic login metadata only |
| Firebase Rules evaluation | **54/54 remote cases passed** | Exact UID + claim + database isolation; not production role authorization |
| Device tokens | Nine copied FCM entries cleared from 13 fields | Copied device registrations are not reused |
| Storage | **271 files, 132,531,735 bytes** verified; fresh tokens; no public bucket IAM | No backup archives in application bucket; lab uploads disabled |
| File references | **137 links remapped across 64 documents; zero unresolved links** | Verified across all 562 restored documents |
| App registrations | **Six cloud registrations and six local configurations verified** | Native signing, APNs and physical-device testing remain separate |
| Cloud Functions | **36/36 active, with recovery guards, correct project environment and private Cloud Run services** | Node.js 22; minimum instances 0, maximum 1 |
| Function exposure | **13/13 unauthenticated HTTP requests rejected; zero scheduler jobs** | Original callable/scheduled behavior remains inactive |
| Payments | Disabled experimental placeholders only | No live Razorpay secrets or transactions used |

Cloud Functions verification is complete, not pending. `function-cloud-verification.json` records all 36 active handlers and private exposure checks, while explicitly retaining `applicationReady: false` and `activationPending: true`.

## Requested Cardiologist test profiles — 3 November 2026

A guarded metadata migration was verified at `2026-11-03T07:13:14.569Z`: all three doctor test accounts now display **Cardiologist 1, Cardiologist 2 and Cardiologist 3**, with specialty **Cardiologist**. Nineteen synthetic documents were patched: doctor profiles, matching user records, patient favorite names, hospital preference keys/names, and the category master display label. Existing UIDs, Auth accounts/credentials, appointment history and the restored default database were unchanged. The original role keys remain `doctor`, `doctor_2`, `doctor_3`; local ports are unchanged. The category master retains its original document ID to preserve references. The console and Flutter lab selectors reflect the requested specialty; historical appointments may still retain their earlier doctor-name snapshots. The app also corrects exact-specialty matching for urgent Cardiologist requests. Use the Cardiac/Chest pain scenario in the app guide; an unrelated General Physician case is not proof of Cardiologist notification routing. The Cardiologist build hash was `91778c34306099f8f881db30f8be20d87ebf36c0f82cf857f807ef7c8525ae4b`; the latest responsive-dialog build is `7b541bbc7999ce37244446f973ec81cd564f96ef149bcd8f26ca566e62451045`. Live Cardiologist request acceptance remains a separate browser check.

The original seed and 36-account expansion remain immutable recovery baselines. Recreating this latest metadata requires the separate optional `test-lab-cardiologists.cjs` review/apply/verify workflow after expansion; see the backup restore guide. Private verification receipt: `test-lab-cardiologists-verification.json`.

## Dummy service OTP — 3 November 2026

The local lab generates **7777** for booking/SOS/duty service codes only. Normal builds retain random generation; Firebase Auth/SMS sign-in is untouched. The separate guarded migration verified **nine existing OTP fields on four appointments**, preserving all non-OTP state across **352 named-database documents**, Auth/passwords and default rules. It did not issue missing codes or reset attempts, locks, expiry, time/payment/status/assignment/location checks. Private receipt: `test-lab-otp-verification.json`, verified at `2026-11-03T08:34:56.345Z`. Live OTP entry/completion remains unverified.

Latest app validation: **61 focused tests passed in each of normal and lab modes**, including six new OTP checks; zero analyzer errors/warnings, one pre-existing nurse style information notice; release Web build passed. Latest `main.dart.js` SHA-256: `d4e2073df9652fda999ff952c48be348882963ba7419f5c4409bf24ee1353d3a`. Do not add repeated test-mode counts to claim distinct tests or a new full-suite run.

## Open the shared role console

On this PC, while its local server runs, open **[http://localhost:8889/](http://localhost:8889/)**. Individual account panels use **localhost ports 8891 through 8926**; the original 14 port bindings are retained. Select account 1, 2 or 3 using grouped checkboxes or panel selectors instead of typing credentials. Only selected panels load (four by default), adding/removing one keeps peers running, and the saved layout contains only account keys and column count. Opening all 36 is allowed but may be slow.

Available families: Patient, Doctor, Nurse, Hospital, Ambulance, Care Physician, Technician, Therapist, Care Agency, Nursing Agency, Technician Agency and Physio Agency — **three identities each**. Each panel shows its exact UID and uses a separate loopback origin and in-memory Firebase Auth session. All share the named synthetic database. Care Physicians 1–3 remain in Sai/Care Agency 1; Care Agencies 2/3 initially have no physician members.

The runtime endpoint supplies only that panel's assigned synthetic credentials. They are not compiled into Flutter assets, placed in URLs or included in Git. The test build verifies project, database, role, UID and signed claims before opening the existing dashboard. Firestore clients are centralized through `AppDatabase`.

**Localhost links work only on the computer running the server.** This console is not a public deployment or mobile download link. Wider access needs a separately reviewed authenticated hosting setup; never expose this credential endpoint to the internet.

## Application validation

| Check | Result |
|---|---|
| Full Flutter suite for 36-account change at `2075c24` | **413 passed, one existing skipped test, zero failures**; not rerun for the subsequent presentation-only Nurse correction |
| Nurse presentation follow-up at `7b5fcc3` | Changed-file analyzer: zero issues; release Web rebuild passed; corrected labels verified in compiled output |
| Cardiologist follow-up at `7ac8a64` | **86 focused identity/SOS/booking tests passed**; all changed files analyze with zero issues; release Web build passed. Full 413-test suite not repeated for this follow-up. |
| Responsive emergency-dialog follow-up at `b403f99` | **21 focused tests passed** (14 layout/action + seven SOS); changed-file analysis clean; release Web build passed. Full suite not repeated for layout-only follow-up. |
| Expanded account-picker/lifecycle checks | **16 Node tests passed**; retained iframes are not reinserted or reloaded when a peer changes |
| Local host/security checks | **23 Python tests passed; one Windows symlink test skipped** |
| Static analysis | Latest changed files: zero errors, warnings or information notices; last full analysis on 2 November: two inherited warnings and 66 information notices |
| Role-lab release Web build | Passed; output `experiments/MYDOXXX/app/build/web-lab` |
| Subsequent login/concurrent-panel diagnostic fix | **53 targeted tests passed; release Web rebuild passed**, commit `1bc5474` |
| Directory-loading/error diagnostic fix | **45 targeted tests passed; Web rebuild passed**, commit `42b75e3`; subsequent `3c3fe48` changes testing instructions only |
| Source ZIP integrity and target isolation | Passed |
| Browser Patient/Doctor smoke check | **New Clinic booking visible to Doctor; scheduled-time OTP block and two-way text chat verified**; full consultation completion not tested |
| Other role workflows | Nurse and Hospital home screens loaded; all-role/full workflow acceptance remains pending |
| APK installation or native release/store submission | Not performed in this setup |
| Private GitHub source backup | Final 112503Z ZIP, README, hash and manifest verified at **`ded30c912337fdb312404d72830f3d1585b01990`**; baseline `78a090f` retained |

The later diagnostic fix shows login stages with a 20-second timeout and prevents duplicate-session eviction between synthetic panels. The following directory fix shows hospital-directory loading/errors and synthetic search diagnostics. Those earlier targeted checks and rebuilds passed. The latest 36-account change subsequently passed the full suite of 413 tests (one skipped) and a release Web build. The corrected test guide follows the actual scheduled Doctor choices, Clinic/Visit and Online: clinic bookings auto-confirm, and booked-time OTP/completion opens follow-up chat. The bounded browser checks below confirm specific behavior in the running build; they do not complete end-to-end acceptance.

## Browser workflow evidence — 3 November 2026

The root agent observed this sequence in the expanded console using only synthetic accounts and the named database:

| Action observed | Result and scope |
|---|---|
| Patient 2 sent a new targeted request to Nurse 1 | The request reached the selected nurse's patient-request flow. |
| Nurse 1 declined that request | The existing immediate-broadcast fallback became available to another nurse. |
| Nurse 2 accepted the broadcast request | Acceptance succeeded and the booking was confirmed. This was a sequential fallback test, not a simultaneous race between providers. |

The test does not yet prove the ignored-request 60-second fallback, a two-nurse acceptance race, subsequent payment/OTP/completion, or nurse follow-up chat. Copied Technician labels and a microscope icon were noticed in the Nurse status dialog during the test. The presentation-only fix at `7b5fcc3` passed analysis and a Web rebuild; compiled output contains NURSE UNAVAILABLE, BROADCASTING TO ALL NURSES and HOME NURSING REQUEST with a medical-services icon. Root browser QA confirmed independent Cardiologist 1 zoom at 80% and Expand/Restore while peer panels kept running. The presentation phone frame was visually confirmed before its height increase. Subsequent live DOM checks measured all four phones at 752.5px height; Patient width remained 337.676px, roles were retained, picker was closed and panel gaps were 6px. No final taller-layout screenshot is claimed because capture failed. See [bounded browser checks](BROWSER-CHECK.md).

A separate read-only audit confirmed appointment `cNEO3F8ljP09prRKNzv0` belongs to `mdxtestpatient2`, is assigned to `mdxtestnurse2`, has status `Confirmed`, records `mdxtestnurse` in `declinedBy`, and still has `paymentStatus: pending`. The audit wrote no Firestore records. Private receipt: `test-room-booking-audit-2026-11-03.json`, checked at `2026-11-03T06:09:23.481Z`.

## Browser smoke evidence — 2 November 2026

Only synthetic identities and the named test database were used.

| Action observed | Result and scope |
|---|---|
| Patient booked Test Doctor for **2 November, 5:00 PM, Clinic/Visit** | A new confirmed appointment was written and appeared live in the Doctor dashboard. This clinic flow auto-confirms; a competing provider acceptance was not tested. |
| Doctor attempted the scheduled OTP stage before the appointment time | The UI correctly blocked the action and displayed a **10-minute wait**. The restriction was not bypassed, and the fresh appointment was not taken through consultation completion. |
| Doctor sent `MYDOXXX test: Doctor to patient - shared Firebase chat works.` | Patient received the message and an unread badge. This used a **seeded completed consultation**, not the newly booked appointment. |
| Patient replied `MYDOXXX test: Patient received your message and replies successfully.` | Doctor received the reply, confirming two-way foreground text chat through the shared Firebase test database. |
| Nurse and Hospital home-screen login | Both dashboards loaded visually. Some empty shift/booked Care Physician panels continued to show spinners; those workflows were not signed off. |

Screenshots: [Doctor received the test booking](evidence/doctor-received-test-booking.png) and [two-way test chat](evidence/two-way-test-chat.png). The read-only booking receipt is `private-backups/mydoxxx-dev-261102/test-lab-booking-confirmed-audit.json`.

This is a limited browser smoke check, not evidence that every role or function works end to end. Remaining checks include fresh consultation completion, other role requests, staffing selection and races, rosters/swaps, and the coordinated emergency sequence. No real patient interaction, payment, SMS or background push was exercised.

Use **Flutter 3.44.1 / Dart 3.12.1** from `C:/Users/Lenovo/Documents/New project/.tools/flutter`; `C:/src/flutter` on PATH is older. This isolated copy pins `pdfrx` to `2.2.24` and has a newly resolved lockfile. Fifteen maintenance tools are quarantined under `disabled-original-tools`; the originals remain in the unchanged received ZIP.

## Actual workflow limits

- **Bookings and text chat:** real shared Firestore records connect existing dashboards. Nurse and Technician have **Patient requests & chats** inboxes alongside their staffing screens. Seeded completed visits unlock the existing 24-hour chat window; they do not prove a freshly booked visit completed successfully.
- **Hospital staffing:** existing client transactions and agency records support synthetic requests and claims. A hospital post accepted through an active care agency now creates its agency duty. Acceptance races, three-person rosters, swaps and agency approvals still need browser walkthrough evidence. The current agency-first offer widens after five minutes to freelancers; it is not a permanent Sai-only restriction.
- **SOS:** the current order is **Patient → Hospital → Doctor → Ambulance**, followed by arrival/OTP stages. Specialty preferences now use the existing SOS taxonomy consistently. Ambulance dispatch is not before doctor assignment. Stale doctor-dialog eligibility and busy-state checks across different simultaneous emergencies remain known gaps. GPS uses synthetic Wakad coordinates; real routing and dispatch are unverified.
- **Provider fallback:** targeted Nurse/Technician decline broadcasts immediately; ignoring broadcasts after 60 seconds only while the Patient status screen remains open. There is no serial provider 1 → 2 → 3 queue. See the scenario guide before testing.
- **Ranking:** existing IT-source ordering uses no-shows ascending, experience years descending, then application time ascending. This work does not implement or verify the proposed complete **Professional Efficiency Score**.
- **Notifications:** foreground request listeners and derived in-app events can update live. Guarded recovered Functions do not operate on the named database. Background FCM, saved server inbox notifications, scheduled expiry and server business enforcement are not demonstrated here.
- **Payments:** a lab-only action marks the current patient's accepted synthetic appointment as a test payment to exercise the next UI step. It does not charge, settle, change wallets, create commissions, refund or pay providers. Razorpay TEST integration, idempotency and webhooks remain separate work.
- **External services:** real SMS, push registration, uploads, real GPS, external links and camera/audio/video calls remain disabled. Enter only fictional test information.
- **Authorization:** exact synthetic identities and server claims restrict this cooperative sandbox. They may work across synthetic records. These rules do not prove production ownership, clinical privacy, state-transition enforcement or pricing integrity.
- **Native platforms:** Android/iOS releases, signing and store acceptance remain unverified. A separate experimental package/bundle is needed for side-by-side installation because the configured `com.mydox.app` can replace the original. Desktop source remains under `desktop-platforms-held` and is not claimed supported.

## Next steps

1. Continue browser acceptance beyond the recorded Patient/Doctor smoke check: fresh consultation completion, other role requests, hospital staffing, competing claims and the four-panel SOS sequence. Record actual results and failures.
2. Investigate the remaining Nurse/Hospital shift and booked-Care-Physician panel spinners before signing off those workflows.
3. Keep future source archives in the private `shrinath4all-del/MYDOXXX` repository, retaining verified final checkpoint `ded30c912337fdb312404d72830f3d1585b01990` and baseline `78a090f`; exclude private exports, passwords, build output, signing material and real records. The prior remote archive remains unchanged; the newly prepared local archive must be uploaded separately to update that checkpoint.
4. Design and test production role/ownership rules and server-side enforcement separately from this synthetic collaboration policy.
5. Restore callable protocols, schedules and external services only through deliberate changes with synthetic acceptance tests; do not simply turn recovery mode off.
6. Test Razorpay TEST mode, device notifications and OTP independently before native release or wider hosting.

## Evidence

- [Role-lab guide](../../experiments/MYDOXXX/app/MYDOXXX-TEST-LAB.md)
- [Source-based multi-account scenarios](../../experiments/MYDOXXX/app/MYDOXXX-TEST-SCENARIOS.md)
- [Role-lab validation](../../experiments/MYDOXXX/app/MYDOXXX-TEST-LAB-VALIDATION.json)
- [Application guide](../../experiments/MYDOXXX/app/MYDOXXX-README.md)
- [Backend source guide](../../experiments/MYDOXXX/backend/README.md)
- [Backend code validation](../../experiments/MYDOXXX/backend/VALIDATION.json)
- [Original ZIP provenance](../../experiments/MYDOXXX/app/MYDOXXX-SOURCE.json)
- [Test-backend setup and verification guide](../../scripts/mydoxxx/TEST-LAB.md)

The older `MYDOXXX-VALIDATION.json` describes the earlier 323-test checkpoint. Use the role-lab receipt and later diagnostic test/build logs for current changes; do not add their test totals together.

Private evidence under `private-backups/mydoxxx-dev-261102` includes `data-final-verification.json`, `function-cloud-verification.json`, `test-lab-verification.json`, `test-lab-access-check.json`, `test-lab-rule-test.json`, `test-lab-index-verification.json` and restore receipts. The original seed plan still matches its saved checksum. The separate 3 November `roles36-v1` migration added 22 accounts and 183 records without rewriting the original 154 test records, 14 credentials or 26 pre-existing Auth identities/password hashes. Its private receipts are `test-lab-expansion-verification.json` and `test-lab-expansion-status.json`. The older late-fixture audit describes the pre-expansion baseline.

Do not publish the private backup directory or its credentials/exports. The protected recovery handover remains in `docs/backend-recovery-2026-11-02/STATUS.md`.
