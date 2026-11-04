> Shared-source import note: follow root SHARED-DEVELOPMENT.md for current
> single-repository setup. The following retains historical checks/recovery
> context; machine paths, separate-repository setup and migrations are not
> instructions to repeat them on the second laptop.

# MYDOXXX experimental workspace

Use **`app/`** for the Flutter application and **`backend/`** for its editable guarded Cloud Functions source. Both are independent local repositories on branch `codex/mydoxxx-experiments`.

The only experimental Firebase project is **`mydoxxx-dev-261102`** (724915428929), displayed as **MYDOXXX**, owned by `shrinath4all@gmail.com`.

- `(default)` preserves **562 restored documents**, with client access denied.
- `mydoxxx-testing` has **36 synthetic identities**, three in each of 12 role families. **333 expected fixture documents** are present; the migration snapshot contained **337 total documents**, including four prior test records. Four unique composite indexes are READY.
- The three doctor test profiles now display **Cardiologist 1–3**, with the **Cardiologist** specialty. The guarded 19-document metadata migration preserved role keys, UIDs, credentials and booking history.
- The original **12 Auth identities** remain unchanged. The additive expansion preserved all 14 existing test credentials, all 26 pre-existing Auth identities/password hashes, and all 154 existing named-database documents. Test accounts use fictional profiles and no real phone numbers.
- All **36 Cloud Functions** are active with recovery guards and private services. All 13 unauthenticated HTTP checks were rejected; no scheduler jobs are active. These functions do not run the named test database's workflows.
- **36/36 synthetic access checks and 54/54 remote Rules cases passed.** All synthetic users were denied access to `(default)` and anonymous access to the test database was denied. The cooperative test policy is not production patient/provider authorization.

The original IT ZIP, CliniGo and protected recovery project `mydox-shrinath-backup-261102` remain separate. The initial setup project `mydoxxx` is retired with billing disabled; do not select it.

## Open the local console

While the server runs on this PC, open **[http://localhost:8889/](http://localhost:8889/)**. Account panels use **localhost ports 8891–8926** and share the named test database; the original 14 bindings are unchanged. Choose any of three Patients, Doctors, Nurses, Hospitals, Ambulances, Care Physicians, Technicians, Therapists, Care Agencies, Nursing Agencies, Technician Agencies or Physio Agencies. Add/remove one panel without reloading the others, use comparison presets, and save your non-sensitive layout. Care Physicians 1–3 remain with Sai/Care Agency 1; Care Agencies 2/3 initially have no physician members.

No login OTP or password needs to be typed. The local viewer displays **Test booking / duty OTP: 7777** for the separately guarded lab flow; this is not an SMS sign-in code and does not enable Firebase phone authentication. Booking-time and assignment checks still apply. Role selectors are larger and bold red, with action buttons on a separate header row. Runtime credentials stay in a private Git-ignored file and are supplied only to the assigned loopback role endpoint. These are not public mobile links; never publish the credential server.

## Source and validation checkpoint

| Item | Verified state |
|---|---|
| Latest Flutter commit | `57379575165107f3fe93228ce7a53287df445627` — compile-time lab service OTP 7777; follows responsive dialogs `b403f99` |
| Role-lab implementation commit | `5c9ae5076563576842a9ceeeec2f794214c4b7a8` |
| Backend source commit | `f21181037c1bba645f623af38f34110b438b0125` |
| Full Flutter lab suite | **413 passed, one skipped, zero failed** at `2075c24`; release Web build passed on 3 November |
| Nurse presentation follow-up | `7b5fcc3`: changed-file analysis clean; Web rebuild and compiled-label checks passed; full suite not rerun for labels/icon only |
| Cardiologist follow-up | `7ac8a64`: **86 focused tests passed**, changed-file analysis clean and release Web rebuild passed; full 413-test suite not repeated |
| Responsive emergency dialogs | `b403f99`: **21 focused tests passed**, changed-file analysis clean, Web release build passed; no full-suite rerun |
| Test service-code follow-up | `5737957`: **61 focused tests passed in normal mode and the same 61 in lab mode**; Web build passed; no full-suite rerun or live OTP-entry claim |
| Local presentation controls | **16 console tests passed**; browser verified independent80% zoom, Expand/Restore and phone shell; taller layout verified by live DOM measurement, no final taller screenshot |
| Expanded console and host checks | **16 Node console tests passed; 23 Python host tests passed, one Windows symlink test skipped** |
| Later diagnostic fix | **53 targeted tests passed; Web rebuild passed** |
| Directory-loading diagnostic fix | **45 targeted tests passed; Web rebuild passed**; following guide correction is documentation only |
| Lab Web output | `app/build/web-lab` |
| Browser Patient/Doctor smoke check | **New confirmed Clinic booking visible to Doctor; scheduled-time OTP block and two-way text chat verified**; full consultation completion not tested |
| Nurse browser fallback check, 3 November | **Patient 2 requested Nurse 1; Nurse 1 declined; Nurse 2 accepted the broadcast and the booking was confirmed.** Sequential fallback only; simultaneous acceptance race and later consultation steps remain untested. |
| Other role workflows | Nurse/Hospital home screens loaded; some shift/booked-Care-Physician panels still showed spinners. Full all-role acceptance remains pending. |
| Private GitHub source backup | **`shrinath4all-del/MYDOXXX`**, final 112503Z source ZIP + README/hash/manifest verified at **`ded30c912337fdb312404d72830f3d1585b01990`**; baseline `78a090f` retained |

Use Flutter 3.44.1 / Dart 3.12.1 from `C:/Users/Lenovo/Documents/New project/.tools/flutter`.

The lab exercises existing booking, staffing and text-chat screens, including Patient request inboxes for Nurse and Technician. Real SMS, FCM, Razorpay/payouts, uploads, GPS and camera/audio calls remain off. Test payment simulation changes only an accepted synthetic appointment. The SOS source order is Patient → Hospital → Doctor → Ambulance. The proposed complete Professional Efficiency Score is not implemented by this work.

On 2 November, a Patient booked a 5:00 PM Clinic/Visit with Test Doctor, and the confirmed appointment appeared live in the Doctor dashboard. The OTP stage correctly showed a 10-minute wait before the booked time; it was not bypassed and the consultation was not completed. Doctor and Patient then exchanged messages in both directions using a **seeded completed consultation**, including the Patient unread badge. See the [bounded browser evidence and screenshots](../../docs/mydoxxx-experiment-2026-11-02/STATUS.md#browser-smoke-evidence--2-november-2026). This is historical smoke evidence. The expanded console has passed the bounded Nurse fallback sequence recorded above; other browser checks are in progress. The prior GitHub source archive remains unchanged. A new local archive is prepared separately and is not automatically uploaded.

## Read next

- [Current handover and remaining work](../../docs/mydoxxx-experiment-2026-11-02/STATUS.md)
- [Role-lab walkthrough and limits](app/MYDOXXX-TEST-LAB.md)
- [Source-based testing scenarios and timing rules](app/MYDOXXX-TEST-SCENARIOS.md)
- [Role-lab validation](app/MYDOXXX-TEST-LAB-VALIDATION.json)
- [Application-specific agent instructions](app/AGENTS.md)
- [Backend source and guarded deployment guide](backend/README.md)
- [Test-backend scripts and credential rules](../../scripts/mydoxxx/TEST-LAB.md)
- [Original ZIP provenance](app/MYDOXXX-SOURCE.json)

Exclude clinical exports, test passwords, signing keys, service-account keys, payment secrets and the `private-backups` directory from GitHub. Complete the remaining browser workflows before full acceptance; refresh the private source archive after subsequent source changes. Local application/backend repositories remain separate; automatic remote synchronization is not claimed.
