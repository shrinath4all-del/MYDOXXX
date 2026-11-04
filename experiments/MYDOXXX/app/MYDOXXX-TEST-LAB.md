# MYDOXXX shared test lab

The test build opens the latest Flutter role dashboards against **synthetic data**
in Firebase project `mydoxxx-dev-261102`, named database **`mydoxxx-testing`**.
It never selects the default database containing the preserved recovery records.
The original IT ZIP, CliniGo and the Srinath recovery project remain separate.

## Open several roles together

Use the local multi-panel console supplied with the workspace. Each role has its
own loopback port, in-memory Firebase login and current app dashboard. The same
named database carries bookings, status changes, rosters and text chat between
panels. No OTP or password needs to be typed by the tester.

Available roles: Patient, Doctor, Nurse, Hospital, Ambulance, Technician,
Therapist, three Care Physicians, and Care Physician, Nurse, Technician and
Physio agencies. The role query keys are in `TestLabConfig.labels`.

The console can open each role with `?role=<key>&autologin=1`. A standalone role
page without autologin shows an **Open role** button. Logging out returns to that
panel's assigned test login. Changing the role query cannot change the credentials
assigned by its local server.

## What to try

1. Patient opens **Find a Doctor**, chooses **General Physician**, and books a
   scheduled **Clinic** or **Online** consultation. These are the current doctor's
   booking options. A clinic booking confirms automatically; watch the same
   booking appear in Doctor's dashboard. At the booked time, use the patient OTP
   to start the consultation, then complete it to enable follow-up chat.
2. Patient books a nurse or technician; in that provider's dashboard open
   **Patient requests & chats**. Accept the same appointment. This new inbox
   closes the previous disconnect between patient bookings and staffing screens.
3. Patient opens My Bookings and chooses **Simulate payment — no charge** for an
   accepted booking requiring payment. Enter the patient's booking OTP at the
   booked time from the provider panel, complete the visit, then use follow-up chat.
4. The seeded recently completed visits let Patient and providers test text chat
   immediately. New visits open follow-up chat after completion, following the
   existing app rule. This is real Firestore message synchronization, not a
   scripted automatic reply.
5. Hospital posts a care-physician locum. Eligible Care Physicians compete for it;
   the existing transaction awards one claimant. The linked agency duty now
   appears for a physician accepting a hospital post through their active agency,
   even when the hospital did not specify an agency on the request.
6. Hospital can also post nurse and technician staffing requirements. Their
   staffing tabs remain separate from patient home-booking inboxes; no second
   booking is created by opening or accepting an existing patient appointment.
7. For SOS use Patient, Hospital, Doctor and Ambulance panels. The current source
   follows **Patient → Hospital → Doctor → Ambulance**, then arrival/OTP stages.
   It does not follow a hospital-to-ambulance-first sequence.

Use test names, messages and booking details only. This is a shared development
dataset, not a workspace for actual patient records or actual clinical decisions.

## Boundaries and limits

- Test access exists only with compile-time `MYDOXXX_TEST_LAB=true` and a loopback
  hostname. The normal application build retains phone login and session persistence.
- Credentials are fetched at runtime from same-origin `/__mydox_test__/login-config`
  with `X-MyDox-Test-Client: 1`. They are not part of the Flutter assets, URL or Git.
  Server-assigned role, Firebase UID, project, database and signed token claims are
  checked before opening a dashboard. Auth persistence is `NONE` in the lab.
  Synthetic test panels do not apply the production one-device SessionGuard, so
  opening a role in another panel cannot expel it. Login displays each connection
  stage with a 20-second deadline and a retry message if it fails.
- All Firestore clients pass through `AppDatabase`; a regression test checks for
  default SDK singleton calls elsewhere. The copied default database stays denied.
- The named test database is a cooperative workspace for the exact test account
  allowlist. Successful multi-role testing does **not** establish production
  patient privacy, record ownership, role authorization or clinical readiness.
- Real SMS, push registration, Razorpay, payouts, camera/audio calls, uploads,
  external links and real GPS remain disabled. Location uses synthetic Wakad
  coordinates. Payment simulation updates one accepted synthetic appointment only;
  it does not charge money, change wallets or create payouts/commissions.
- Foreground Firestore listeners update requests and existing derived notifications.
  The guarded recovered Cloud Functions do not operate on this named database.
  Background push, saved server inbox messages, scheduled expiry, automatic pricing
  enforcement, refunds and payment webhooks are not being tested here.
- Latest-source care-physician shortlisting uses its existing no-show/experience/
  application ordering. This work does not implement or verify the proposed
  comprehensive Professional Efficiency Score.
- Android/iOS release builds, store publication and public hosting are outside
  this local browser test setup.

## Development verification

Use Flutter 3.44.1 / Dart 3.12.1 from
`C:/Users/Lenovo/Documents/New project/.tools/flutter`.

```text
flutter test --no-pub
flutter build web --release --no-pub --dart-define=MYDOXXX_TEST_LAB=true --output=build/web-lab
```

The full suite after these changes passed **376 tests**, with **one existing
skipped test** and no failures. The release Web build passed at `build/web-lab`. Static analysis reports zero
errors, two inherited warnings and 66 information notices. Browser checks are
recorded separately by the main implementation handover. App tests cover the database boundary, local
credential origin/role checks, synthetic-payment restrictions, patient request
actions and hospital-agency routing. Browser validation is separately necessary
for permissions, data schemas, concurrent acceptance and the actual end-to-end UI.

The diagnostic follow-up build also passed. Its 53 targeted regression tests
passed; changed-file analysis has no errors or warnings and one style notice.
The local host uses CPU CanvasKit to avoid GPU context exhaustion when several
Flutter panels are open together.

Doctor search now reports hospital-location loading and query errors explicitly;
it no longer treats an absent hospital snapshot as an empty directory. If a lab
search is empty, its diagnostic text lists synthetic directory counts, matching
hospital names, cache/server source and the synthetic patient position. These
diagnostics are compiled out of the normal build. The live seeded doctor and
hospital were checked and match within approximately 125 metres; no eligibility
or radius checks were bypassed.
