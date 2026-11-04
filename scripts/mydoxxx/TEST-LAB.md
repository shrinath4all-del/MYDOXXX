> Shared-source import note: follow root SHARED-DEVELOPMENT.md for current
> single-repository setup. The following retains historical checks/recovery
> context; machine paths, separate-repository setup and migrations are not
> instructions to repeat them on the second laptop.

# MYDOXXX isolated live test lab

This lab tests the actual Flutter screens against shared Firebase data. It uses only synthetic records in the STANDARD/NAM5 named database `mydoxxx-testing`, in project `mydoxxx-dev-261102` (724915428929). The restored `(default)` database keeps its existing deny-all rules. No original project, CliniGo, abandoned project, or preserved backup is writable through this setup.

## Using the local test room

Open `http://localhost:8889/` on the PC running the host. Select the accounts you need; only selected screens load. The 36 accounts use separate origins on ports 8891–8926 and share the synthetic named database. Role keys and UIDs do not change when the display label is Cardiologist 1, 2 or 3.

- **iPhone frame:** on by default for presentation. The toolbar toggle switches all screens to plain view without restarting them. The status/island strip and bottom home indicator sit outside the app viewport; they cannot cover app buttons. This is local viewer decoration, not a change to the mobile app or backend. Normal phone presentation is now 25% taller than its earlier computed whole-phone height, including its status/home strips and bezel; width is unchanged. Panel gaps are 6px and phone side gutters are 4px. Expanded phones stay bounded by the viewport, and plain view keeps its original height.
- **Zoom − / +:** changes only that screen, from 60% to 140%. Click the percentage to reset. Zooming out increases the app's logical viewport so more of a dialog fits. Narrow phone frames fit the logical app width automatically; zooming in may require scrolling the individual viewport.
- **Expand / Restore:** makes one screen larger while retaining its iframe and the other running sessions. Restore, a backdrop click, or Escape while console controls are focused returns to the room. The Restore button stays outside the app and visible. Keyboard events inside a cross-origin app iframe do not bubble to the parent console.
- **Choose accounts:** collapse the picker for more room. Adding/removing one account preserves its peers. Each header shows the exact UID; separate-tab links open safely.

Only non-sensitive presentation/layout choices are saved locally. The phone-frame switch and zoom/expand controls never call Firebase or change appointments. Removing a screen closes that local view; shared test records remain saved. See [browser checks and limits](../../docs/mydoxxx-experiment-2026-11-02/BROWSER-CHECK.md) for observed results.

## Test booking / duty OTP: 7777

The compile-time `MYDOXXX_TEST_LAB` build now generates **7777** for service booking, SOS and duty-arrival codes. This is not a Firebase Authentication/SMS login code. Normal builds use random four-digit service codes. Twelve generation sites across nine existing files use the shared `ServiceOtp` factory; validators still compare each record's stored code and retain booked-time, payment, status, assignment, attempt-lock, expiry and location checks.

A separate guarded migration changed **nine existing code fields on four synthetic appointments** to 7777. Verification at `2026-11-03T08:34:56.345Z` compared all **352 named-database documents**: every non-OTP field remained unchanged. Auth/passwords, default rules and the restored default database were untouched. Unissued/missing codes were not created, and timestamps, expiry, failed attempts, locks and payments were not reset. Use a newly issued valid code when the duty flow requires issuance; 7777 does not bypass expired or unissued-code restrictions.

App commit `57379575165107f3fe93228ce7a53287df445627` passed **61 focused tests in normal mode and the same 61 in lab mode**, including six new OTP tests. Changed-file analysis had zero errors/warnings and one pre-existing style information notice; release Web build passed. Live OTP entry/completion has not yet been claimed. The local viewer notice is deliberately labelled **Test booking / duty OTP**, not login OTP.

For a newly restored lab only, the reviewed existing-record helper supports:

```text
node scripts/mydoxxx/test-lab-otp-check.cjs
node scripts/mydoxxx/test-lab-otp.cjs review
# Inspect the private review; keep test activity idle through apply/verify.
node scripts/mydoxxx/test-lab-otp.cjs apply
node scripts/mydoxxx/test-lab-otp.cjs verify
```

Only the first command is offline. The migration has already been applied on the current lab. Review/apply enforce exact project/database/participants and field masks, with atomic update-time preconditions. Keep `test-lab-otp-review.json`, `test-lab-otp-applied.json` and verification receipts private; the first two contain record preimages/rollback data and must never be included in a source archive.

## Three identities per role — additive expansion, 3 November 2026

The original 14 identities and 150 seed records remain the baseline. The expanded catalogue has **36 identities: three of each of 12 role families**. The first identity keeps its existing key; additional identities use `_2` and `_3`. The existing Care Physician 2/3 identities are reused, so only **22 Auth accounts** are added. Original port ordering is unchanged. Console labels explicitly show person 1, 2 or 3; existing saved profile names are preserved.

Run the offline and read-only review first, then the reviewed migration:

```powershell
node scripts/mydoxxx/test-lab-local-check.cjs
node scripts/mydoxxx/test-lab.cjs expand-dry-run
# Inspect private-backups/mydoxxx-dev-261102/test-lab-expansion-review.json
node scripts/mydoxxx/test-lab.cjs expand
node scripts/mydoxxx/test-lab.cjs expand-verify
node scripts/mydoxxx/test-lab.cjs verify
node scripts/mydoxxx/test-lab.cjs access-check
node scripts/mydoxxx/test-lab-rule-check.cjs
```

`expand-dry-run` only reads the cloud and writes a private local review. It recursively inventories **every existing named-database document**, including user-created bookings/chat and subcollections beneath missing parent documents. It generates no passwords. At the initial review the database contained **154 documents**, and the add-only plan contained **183 new documents**.

`expand` accepts a review at most 24 hours old, rechecks the exact database edition/location/project number/owner and the entire existing-data digest, then appends 22 random credentials by atomic replacement of the private credential file. The original 14 credential-entry digests must remain equal. Existing Auth identities, including their password hashes and claim fields, are fingerprinted privately; the migration never resets their passwords or replaces their claims. New account and new document attempts are recorded before each operation so retries resume safely. New Firestore writes use `currentDocument.exists: false`; an occupied path without the migration receipt stops the run. Existing profiles, appointments, messages, preferences, agency membership and availability are not rewritten.

The new rules differ only by the exact synthetic UID-to-role allowlist. Before changing the named release, the script compiles the rules and evaluates **54 allow/deny cases**. The `(default)` release must still exactly match its saved deny-all policy. The script never deploys Auth provider configuration, changes billing, enables Identity Platform or sends real communications. If existing test activity changes the baseline during the migration, verification stops and reports it; it does not overwrite records to force a match. Keep testing activity idle where practical, without discarding unsaved screens. A new dry-run may be taken before a not-yet-started migration; once a migration receipt exists, preserve it and investigate discrepancies.

`expand-verify` compares the final snapshot against the saved full baseline after excluding only the 183 planned new paths. This is the immediate migration-preservation check: after testers intentionally edit old data, that historical digest will naturally no longer match. Use ordinary `verify` for later fixture-presence/isolation checks. Private receipts are `test-lab-expansion-review.json`, `test-lab-expansion-status.json`, `test-lab-expansion-before-documents.json` and `test-lab-expansion-verification.json`.

In the original expansion fixtures, Doctor 2/3 are verified, online General Physicians with exact matching Hospital 2/3 names/UIDs in the same nearby synthetic Wakad area. Patient 2 prefers Doctor 2; Patient 3 prefers Doctor 3; original preferences remain unchanged. New nurses, technicians and therapists use matching numbered agencies and nearby service areas. The original three Care Physicians retain their existing agency team. Fourteen days of availability are added for new appointment providers, plus **12 separately identified completed-consultation fixtures** for Patient 1/2/3 to test chat with their numbered Doctor, Nurse, Technician and Therapist. Those fixtures do not establish that a real fresh consultation completed.

The later user-requested `test-lab-cardiologists.cjs` migration changes the three current doctor profiles to **Cardiologist 1–3** with specialty **Cardiologist**, preserving UIDs, Auth, credentials and appointment history. Its 19-document verification is recorded in the private Cardiologist receipt; recreate it separately after expansion if restoring this latest setup.

## Original 14-identity setup

The original setup commands remain for receipt-compatible recovery; **use the expansion commands above to extend the existing lab**, not a fresh seed or a password reset:

```powershell
node scripts/mydoxxx/test-lab-local-check.cjs
node scripts/mydoxxx/test-lab.cjs prepare
node scripts/mydoxxx/test-lab.cjs verify
node scripts/mydoxxx/test-lab.cjs access-check
```

Only the first command is offline. `prepare` creates the named database if missing, creates fourteen synthetic Auth accounts, sets exact test claims, installs rules on the named database only, requests the four composite indexes already declared by the IT app, and seeds the UI-compatible fixtures. It never enables Auth providers or upgrades Basic Auth. Email/password must already be enabled. Existing records are never replaced. A matching private receipt is required for resumption.

The private credentials are generated on the first prepare call at `private-backups/mydoxxx-dev-261102/test-lab-credentials.json`, which must be Git-ignored. Never copy this file to Flutter assets, Netlify, public Hosting, the repository, or a handover document. Passwords are random, synthetic emails use `.invalid`, and no phone numbers, SMS messages, emails, payment calls or push notifications are created.

The JSON contains `projectId`, `projectNumber`, `databaseId`, `createdAt`, and `accounts`. Role-family keys are `patient`, `doctor`, `nurse`, `hospital`, `ambulance`, `care_physician`, `technician`, `therapist`, `agency_care`, `agency_nurse`, `agency_technician`, `agency_physio`, with `_2`/`_3` variants after expansion. Each entry has `uid`, `email`, `password`, `name`, `role`, `roleKey`, and `collection`. UIDs have no underscores because the current chat ID parser uses `_` as the participant delimiter. The signed `role` is the unsuffixed family (`care_physician` for all three), or `agency` for all agency families. Agency profiles carry their corresponding agency type in Firestore. Public catalogues may expose only synthetic keys/UIDs, labels, family, person and loopback URL; never expose passwords or the entire private JSON.

The local loopback server should expose only its configured role via `/__mydox_test__/login-config`, using no-store, exact Host/Origin checks and no wildcard CORS. Return `{projectId,databaseId,roleKey,role,uid,email,password}`. Never return the whole credentials file. Four or more localhost ports give separate origin storage for simultaneous app sessions. The Flutter lab must use the named Firestore database for all reads, writes, session claims, profile reads, images, and chat. Calling the default database must fail closed.

Fixtures include profiles, master categories and prices, local asset references, agency memberships, fourteen days of appointment availability, and recent synthetic completed consultations to unlock the existing 24-hour chat window. Seeded prices are illustrative. To verify the real notification/request pipeline, create a new booking in the Patient panel; do not mistake seeded completed records for successful live tests.

`verify` only reads the cloud, then writes its verification report locally. It compares all 562 restored clinical documents, original Auth identity fields, and default rules with the preserved state. Lab records may evolve during testing, so it verifies their presence and synthetic markers without overwriting them. After expansion it checks both the original 150 and new 183 fixtures. `access-check` signs into every synthetic user in the saved credentials file (14 initially; 36 after expansion), confirms named-database reads work, and proves unauthenticated users and test users accessing `(default)` are denied. Sign-in updates only the synthetic accounts' login timestamps; it writes no Firestore records. It is not a production security audit.

The test rules intentionally allow the exact claimed test users (14 initially; 36 after expansion) to cooperate across this wholly synthetic database. They do not implement production patient/provider row permissions, price enforcement, ranking verification, or billing. Server-side original functions still target the locked restored database; they are not silently connected to the lab. Realtime in-app snapshots can be tested. Real SMS, FCM delivery, Razorpay settlement, attachments in cloned Storage, and live medical coordination remain excluded.

Rules review: exact project/database isolation; authenticated allowlisted UID plus server-set `mydoxTest`, `testDatabase`, and `role` claims; client profile changes cannot grant claims; no anonymous access. The lab-wide collaboration grant deliberately does not limit per-document data types, sizes or editing another synthetic profile. It therefore cannot be described as production authorization: an authorized tester can corrupt other synthetic records or consume quota. Credentials must remain loopback-only. The installed Firestore rules-author/rules-creation skill was unavailable after renewed discovery; the installed Firebase rules auditor checklist and [official Firebase Rules conditions guide](https://firebase.google.com/docs/firestore/security/rules-conditions) and [named-database guide](https://firebase.google.com/docs/firestore/manage-databases) were used for this narrow test-only allowlist expansion.
