# ZIP16 update for the private BFAST test room

Reviewed source: `mydox-master (16).zip`, received 20 November 2026.
SHA256: `2b7c56d519dbfbe2519d05fc97f26ffd3ccbadc6f7f11ce93564762125c5c963`.

This archive is byte-for-byte identical to ZIP14. The Antigravity/CliniGo
checkout already contains that reviewed delivery. This update brings the
separate GitHub cloud-test source forward from its selectively imported ZIP13
baseline, without replacing either checkout wholesale.

## Included changes

- Care-physician and nurse agency calendars, daily duties, leave requests,
  leave history, and staff-on-leave views.
- Agency staff photographs and profile improvements, hospital request and
  earnings views, and administrator freelancer visibility.
- Hospital-category care-duty pricing and validation, with matching pure
  client/server calculation tests. Invalid or non-finite rates and margins
  cannot silently produce misleading totals.
- Compatibility for older agency leave records, scoped to the relevant
  agency; resolved leave history remains visible and cannot be decided again.
- Incoming email-registration/login source, with external account creation,
  password reset and email login disabled in the synthetic lab. Administrator
  login requires an already provisioned administrator role; it does not grant
  that role on sign-in.

## Preserved cloud-test behavior

The existing 36 test identities, Google operator sign-in gate, Netlify team
access, role selector, cardiologist labels, service OTP `7777`, phone frames,
startup/retry behavior, emergency protections, and version footer remain.
All app data access continues through `AppDatabase`, using the named
`mydoxxx-testing` database in the experiment. India-time helpers remain in use.
External email, SMS, real payment, live push and other guarded external actions
are not enabled by this merge.

## Policy change inherited from the IT delivery

The uploaded staffing code removes its prior automatic no-show booking
restriction and automatic reliability/rank penalty. This import retains that
delivery behavior. It does not replace or finalize the separate proposed
100-point Professional Efficiency Score. Any future penalty policy should be
explicitly reviewed, evidenced and appealable before activation.

## Deliberately not deployed or replaced

Firebase configuration, Authentication providers/users, rules, indexes,
Storage, billing and backend deployments are unchanged. The preserved
default databases and CliniGo remain untouched.

Updated `app/functions_push` files are source and offline-test material only.
They retain upstream default-database assumptions and must not be deployed
to the named synthetic database without a separate backend review. Therefore
new server-side push automation and authoritative server pricing are not
claimed live by this static website update. No new undeployed callable is
required by the merged screens.

The archive's Android-only `screen_protector` Gradle override is not imported:
that dependency is absent from the cloud branch. Cloud dependency locks,
Firebase options, web startup code and the retained OTP compatibility widget
are preserved. No APK was supplied or generated in this update.

## Release verification

The existing CI now runs the complete offline Flutter test suite once, then
repeats the isolation/time guards in local and cloud lab modes. It also runs
the pure server-pricing tests, existing viewer/broker/package checks, the
release web build and the strict static-output secret scan. A successful
reviewed merge publishes through the existing main-branch Netlify pipeline;
the website footer identifies the exact commit and build time.

Runtime smoke checks should cover agency calendar drill-down, leave/history
views, freelancer visibility and simultaneous role sessions. Offline tests
and synthetic sessions do not establish production clinical, privacy,
payment, external notification or staffing readiness.
