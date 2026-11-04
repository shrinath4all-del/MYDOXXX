# MYDOXXX isolated live test lab

This lab tests the actual Flutter screens against shared Firebase data. It uses only synthetic records in the STANDARD/NAM5 named database `mydoxxx-testing`, in project `mydoxxx-dev-261102` (724915428929). The restored `(default)` database keeps its existing deny-all rules. No original project, CliniGo, abandoned project, or preserved backup is writable through this setup.

Run from the workspace root, in order:

```powershell
node scripts/mydoxxx/test-lab-local-check.cjs
node scripts/mydoxxx/test-lab.cjs prepare
node scripts/mydoxxx/test-lab.cjs verify
node scripts/mydoxxx/test-lab.cjs access-check
```

Only the first command is offline. `prepare` creates the named database if missing, creates fourteen synthetic Auth accounts, sets exact test claims, installs rules on the named database only, requests the four composite indexes already declared by the IT app, and seeds the UI-compatible fixtures. It never enables Auth providers or upgrades Basic Auth. Email/password must already be enabled. Existing records are never replaced. A matching private receipt is required for resumption.

The private credentials are generated on the first prepare call at `private-backups/mydoxxx-dev-261102/test-lab-credentials.json`, which must be Git-ignored. Never copy this file to Flutter assets, Netlify, public Hosting, the repository, or a handover document. Passwords are random, synthetic emails use `.invalid`, and no phone numbers, SMS messages, emails, payment calls or push notifications are created.

The JSON contains `projectId`, `projectNumber`, `databaseId`, `createdAt`, and `accounts`. Account keys: `patient`, `doctor`, `nurse`, `hospital`, `ambulance`, `care_physician`, `care_physician_2`, `care_physician_3`, `technician`, `therapist`, `agency_care`, `agency_nurse`, `agency_technician`, `agency_physio`. Each entry has `uid`, `email`, `password`, `name`, `role`, `roleKey`, and `collection`. UIDs have no underscores because the current chat ID parser uses `_` as the participant delimiter. Agency entries have role `agency` and their corresponding agency type in Firestore.

The local loopback server should expose only its configured role via `/__mydox_test__/login-config`, using no-store, exact Host/Origin checks and no wildcard CORS. Return `{projectId,databaseId,roleKey,role,uid,email,password}`. Never return the whole credentials file. Four or more localhost ports give separate origin storage for simultaneous app sessions. The Flutter lab must use the named Firestore database for all reads, writes, session claims, profile reads, images, and chat. Calling the default database must fail closed.

Fixtures include profiles, master categories and prices, local asset references, agency memberships, fourteen days of appointment availability, and recent synthetic completed consultations to unlock the existing 24-hour chat window. Seeded prices are illustrative. To verify the real notification/request pipeline, create a new booking in the Patient panel; do not mistake seeded completed records for successful live tests.

`verify` only reads the cloud, then writes its verification report locally. It compares all 562 restored clinical documents, original Auth identity fields, and default rules with the preserved state. Lab records may evolve during testing, so it verifies their presence and synthetic markers without overwriting them. `access-check` signs into the fourteen synthetic users, confirms named-database reads work, and proves unauthenticated users and test users accessing `(default)` are denied. Sign-in updates the synthetic accounts' login timestamps; it writes no Firestore records. It is not a production security audit.

The test rules intentionally allow the exact fourteen claimed test users to cooperate across this wholly synthetic database. They do not implement production patient/provider row permissions, price enforcement, ranking verification, or billing. Server-side original functions still target the locked restored database; they are not silently connected to the lab. Realtime in-app snapshots can be tested. Real SMS, FCM delivery, Razorpay settlement, attachments in cloned Storage, and live medical coordination remain excluded.

Rules review: exact project/database isolation; authenticated allowlisted UID plus server-set `mydoxTest`, `testDatabase`, and `role` claims; client profile changes cannot grant claims; no anonymous access. The lab-wide collaboration grant deliberately does not limit per-document data types or editing another synthetic profile. Do not use this rule set for real people or advertise it as production authorization. The installed Firestore rules-author/rules-creation skill was unavailable; the installed Firebase rules auditor checklist and official Firebase Rules documentation were used for this narrow test-only policy.
