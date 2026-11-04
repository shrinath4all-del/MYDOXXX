# MYDOXXX experimental workspace

Use **`app/`** for the Flutter application and **`backend/`** for its editable guarded Cloud Functions source. Both are independent local repositories on branch `codex/mydoxxx-experiments`.

The only experimental Firebase project is **`mydoxxx-dev-261102`** (724915428929), displayed as **MYDOXXX**, owned by `shrinath4all@gmail.com`.

- `(default)` preserves **562 restored documents**, with client access denied.
- `mydoxxx-testing` has **150 initial synthetic records** and **14 dummy-role identities** using real Firebase sign-in and shared data. Four composite indexes are READY.
- The original **12 Auth identities** remain unchanged; the 14 test users have no real phone numbers.
- All **36 Cloud Functions** are active with recovery guards and private services. All 13 unauthenticated HTTP checks were rejected; no scheduler jobs are active. These functions do not run the named test database's workflows.
- **14/14 synthetic access checks and 32/32 remote Rules cases passed.** The cooperative test policy is not production patient/provider authorization.

The original IT ZIP, CliniGo and protected recovery project `mydox-shrinath-backup-261102` remain separate. The initial setup project `mydoxxx` is retired with billing disabled; do not select it.

## Open the local console

While the server runs on this PC, open **[http://localhost:8889/](http://localhost:8889/)**. Role panels use **localhost ports 8891–8904** and share the named test database. Choose Patient, Doctor, Nurse, Hospital, Ambulance, Technician, Therapist, three Care Physicians or one of four agency identities.

No OTP or password needs to be typed. Runtime credentials stay in a private Git-ignored file and are supplied only to the assigned loopback role endpoint. These are not public mobile links; never publish the credential server.

## Source and validation checkpoint

| Item | Verified state |
|---|---|
| Latest Flutter commit | `3c3fe483c744494c2a9512643b040ad1c78b0557` — corrected Doctor testing guide; follows directory-loading diagnostics at `42b75e36da24ddbd1700c3d7886656b1a91b1c04` |
| Role-lab implementation commit | `5c9ae5076563576842a9ceeeec2f794214c4b7a8` |
| Backend source commit | `f21181037c1bba645f623af38f34110b438b0125` |
| Full Flutter lab suite | **376 passed, one skipped, zero failed** |
| Later diagnostic fix | **53 targeted tests passed; Web rebuild passed** |
| Directory-loading diagnostic fix | **45 targeted tests passed; Web rebuild passed**; following guide correction is documentation only |
| Lab Web output | `app/build/web-lab` |
| Browser role/workflow acceptance | **Pending completion** |
| Private GitHub source backup | **`shrinath4all-del/MYDOXXX`**, source ZIP + README/hash/manifest verified at commit **`78a090f`** |

Use Flutter 3.44.1 / Dart 3.12.1 from `C:/Users/Lenovo/Documents/New project/.tools/flutter`.

The lab exercises existing booking, staffing and text-chat screens, including Patient request inboxes for Nurse and Technician. Real SMS, FCM, Razorpay/payouts, uploads, GPS and camera/audio calls remain off. Test payment simulation changes only an accepted synthetic appointment. The SOS source order is Patient → Hospital → Doctor → Ambulance. The proposed complete Professional Efficiency Score is not implemented by this work.

## Read next

- [Current handover and remaining work](../../docs/mydoxxx-experiment-2026-11-02/STATUS.md)
- [Role-lab walkthrough and limits](app/MYDOXXX-TEST-LAB.md)
- [Role-lab validation](app/MYDOXXX-TEST-LAB-VALIDATION.json)
- [Application-specific agent instructions](app/AGENTS.md)
- [Backend source and guarded deployment guide](backend/README.md)
- [Test-backend scripts and credential rules](../../scripts/mydoxxx/TEST-LAB.md)
- [Original ZIP provenance](app/MYDOXXX-SOURCE.json)

Exclude clinical exports, test passwords, signing keys, service-account keys, payment secrets and the `private-backups` directory from GitHub. Finish browser verification and refresh the verified remote source archive after final UI changes. Local application/backend repositories remain separate; automatic remote synchronization is not claimed.
