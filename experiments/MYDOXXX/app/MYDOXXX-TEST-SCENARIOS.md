# MYDOXXX: test three people in each role

Source audit and test instructions, 3 November 2026. Use the loopback console
and synthetic records only. These are existing Flutter workflows, not a claim
of production readiness or background push delivery.

## Choose screens

Patient, Doctor, Nurse, Hospital, Ambulance, Care Physician, Technician,
Therapist, Care Agency, Nurse Agency, Technician Agency and Physio Agency each
have identities 1, 2 and 3: **36 independent accounts** in `mydoxxx-testing`.
Base keys denote person 1 (`doctor`); other keys are `doctor_2` and `doctor_3`.
The doctor family now displays **Cardiologist 1–3** while its role and keys stay
`doctor`, `doctor_2`, `doctor_3`. Original identities and historical appointments
are preserved. Credentials remain assigned by each local
server and are validated against the Firebase UID, role and signed test claims.

Admin is excluded because it manages privileged configuration and verification.
Separate Pharmacy, Diagnostic Centre and Equipment Vendor dashboards do not
exist in this source; a login label cannot substitute for those implementations.

## Scheduled doctor booking

Open Patient 1 and Cardiologist 1. Patient: **Find a Doctor → Cardiologist →
Cardiologist 1 → Clinic** (or Online), then choose an available future date/time.
A clinic booking confirms automatically and should appear for Cardiologist 1. This
is not an acceptance race. At the booked time, start with the patient OTP,
complete the consultation, and test follow-up chat. Camera/audio calls remain
disabled in the lab.

## Nurse decline, ignore and first acceptance

Open **Patient 2 + Nurse 1 + Nurse 2 + Nurse 3**.

1. Patient 2: **Nurses**, choose Nurse 1 and an available future home booking.
   The current multi-day option is 3–7 days, 12:00–18:00 daily. Keep the status
   dialog open.
2. Nurse 1: **Patient requests & chats → Decline**. That same appointment becomes
   a broadcast. Eligible Nurse 2 and Nurse 3 should see it; Nurse 1 cannot reclaim
   a declined request.
3. Accept from Nurse 2, then try Nurse 3. Only one provider should be recorded;
   the losing attempt must not overwrite the winner or create another booking.
4. For an ignore test, make a fresh request to Nurse 1 and do nothing. Keep the
   patient status dialog open for 60 seconds. Its timer broadcasts to other
   eligible nurses. This is a broadcast, not a serial Nurse 1→2→3 queue.
5. Where payment is required, Patient uses **Simulate payment — no charge**.
   OTP/start, completion and follow-up chat use the same appointment.

Technician patient requests have the equivalent direct-request/decline/
60-second dialog-broadcast flow. Therapist requests have additional agency
routing; do not assume all provider types use identical dispatch rules.

The 60-second timer starts when the status dialog opens. Closing it stops the
timer; reopening restarts it. The named test database has no active server
scheduler or FCM dispatch. Background-tab throttling can delay timers. Keep the
relevant panels open. Durable unattended routing remains work to review.

## SOS: hospital, preferred doctor, other doctors, ambulance

Use Patient 1, Hospital 1, Cardiologist 1–3 and Ambulance 1–3; switch visible panels
when the stage changes. Doctors must be Online and free of another emergency.

1. Patient: **Emergency help → Yes, book emergency → Cardiac / Chest pain → Continue
   → Send an ambulance to me**. Use fictional answers; keep the tracker visible.
   Cardiac / Chest pain matches the current Cardiologist test profiles. Something
   else and Chest / Breathing do not match these profiles under the existing
   taxonomy; do not use those categories for this cardiology demonstration.
2. Hospital 1 accepts. For a hospital race, open Hospital 1–3 before submitting:
   declining removes only that hospital; the first successful acceptance wins.
3. Preferred Cardiologist 1 gets the first 60-second window. The November 3 fix maps
   hospital preferences saved under **Cardiologist** to **Cardiac / Chest pain**
   using the existing candidate taxonomy. Verification, online status and the
   4 km preferred-distance check still apply.
4. Let Cardiologist 1 ignore or decline. Decline excludes that doctor but does not
   shorten the preferred window. After 60 seconds Cardiologist 2 and Cardiologist 3 can see
   the request; their streams refresh every 15 seconds, so allow that interval.
5. Accept from Cardiologist 2 and attempt Cardiologist 3. Only one doctor should be assigned.
   The ambulance stage opens only after doctor acceptance.
6. Decline from one ambulance and accept from another. A second acceptance for
   the same request must lose. Continue pickup/hospital-arrival OTP steps. The
   doctor has a separate arrival OTP. Verify assigned fields on all panels.

| Stage | Existing timing |
| --- | --- |
| Hospital search | 4 km initially, 6 km after 60 seconds, 8 km after 120 seconds |
| Doctor preference | Eligible preferred doctors within 4 km for 60 seconds, if any exist |
| Wider doctor search | 4 km after preference, then 6/8 km at subsequent 60-second steps |
| Ambulance search | From patient location: 4/6/8 km at 60-second steps |
| Unallocated SOS pipeline | Five minutes total from creation, not per stage |
| Allocated arrival targets | 15/25/30 minutes for up to 4/6/8 km |

When allocation expires, an unaccepted request can be deleted; a partly
accepted one stays as **Expired**. Open clients invoke cleanup in this lab.
An already dispatched ambulance is not expired by that five-minute rule.
Decline does not instantly enlarge the radius or create a new request.

## Hospital locum and agency team

Hospital posts a future care-physician locum. Open Care Physician 1–3 and Care
Agency 1. Existing CP1–3 keep their original synthetic agency association.

- Locum: first valid transaction wins; later claims lose. A decline excludes
  only that physician. Other eligible physicians can still claim.
- Agency hospital duties link to the agency calendar/earnings record. Independent
  patient home visits are not attributed to that agency by this integration.
- Full-time team: multiple physicians apply; agency reviews and allocates.
  Applying is not winning a single locum slot.
- The existing shortlist sorts fewer no-shows, more experience, then earlier
  applications. It is not the proposed 100-point Professional Efficiency Score.
  Three applicants cannot demonstrate a populated Top 5/10.
- Inherited hospital staffing rules offer agency members first for five minutes,
  then permit freelancers. This differs from the earlier Sai-only policy and
  needs an explicit product decision; this update does not change it.
- Unclaimed shifts stop matching after their start time. Adding accounts does
  not introduce guaranteed automatic replacement or a new no-response queue.

Nurse/Technician hospital staffing stays separate from patient appointments.

## Limits to record with test results

Same-case acceptance is transactional. Some provider-busy checks happen before
the transaction, so one provider accepting two different cases simultaneously
needs a separate concurrency test and server-enforcement review. The inherited
doctor emergency pop-up also needs explicit open-status and prior-decline
rechecks inside its claim transaction; a stale pop-up after cancellation or
expiry must be tested before treating the workflow as reliable. These tests
do not establish production privacy, role authorization or clinical readiness.
Real SMS, push, Razorpay, payouts, uploads, live GPS and camera calls are disabled.
Record each scenario as passed, failed or not tested; do not infer all flows
passed from a successful login.

Source references: `TestLabConfig`; `SosService`; `FirestoreService` request,
preference and stream methods; `NurseStatusDialog`; `TechnicianStatusDialog`;
`DoctorEmergencyAlertDialog`; `CarePhysicianService.claimShift/shortlist`.
