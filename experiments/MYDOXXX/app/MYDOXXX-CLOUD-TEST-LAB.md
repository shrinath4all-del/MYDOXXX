# MYDOXXX cloud panel login contract

The cloud test build uses the same 36 synthetic identities and named
`mydoxxx-testing` database as the local lab. It is a cooperative test workspace,
not production clinical access. The default database and protected backends are
not selected by this build.

## Open the hosted test lab

URL: **https://mydoxxx-live-test.netlify.app/**

This site is deployed with private Netlify team access, as requested. There are
two separate sign-in layers:

1. Pass Netlify's site-access screen using an account with access to the
   **kunal110284 Netlify team**. A Google login inside the app cannot replace
   this Netlify team membership.
2. Inside the MyDox test portal, choose Google sign-in and use
   **shrinath4all@gmail.com**, the authorized test operator. Then open the
   required synthetic role panels.

The hosted app and shared Firebase test backend run in the cloud. A phone or
computer with internet access can open the site; the development PC and local
test server do not need to remain running. A person receiving only the URL
still needs both access layers above. Do not share an account password to grant
access.

Each issued cloud role session lasts up to **8 hours**. Reopen the role from the
authenticated portal when the session expires. Role logins are held in memory,
so a page reload obtains a fresh authorized role login rather than reusing a
stored test password.

## Verification status — 4 November 2026

- The private, team-protected site has been deployed at the URL above.
- The focused login/isolation suite passed **156 tests in each** normal,
  local-lab and cloud-lab configuration. Targeted static analysis found no issues.
- The separate cloud release build completed, with `/panel/` as its base path.
  Its compiled JavaScript does not contain the local password-login endpoint.
- Successful Google operator sign-in through the deployed browser UI is still
  being checked. Full hosted multi-role workflow testing is therefore not yet
  confirmed. Deployment and passing code checks do not establish that every
  role or clinical workflow has passed end-to-end testing.

## Explicit build boundary

Build with all of:

```text
--dart-define=MYDOXXX_TEST_LAB=true
--dart-define=MYDOXXX_CLOUD_TEST_LAB=true
--dart-define=MYDOXXX_TEST_ORIGIN=https://mydoxxx-live-test.netlify.app
--base-href=/panel/
```

Only `https://mydoxxx-live-test.netlify.app/panel/` is accepted. Preview domains,
other Netlify sites, other paths and non-HTTPS origins are rejected. Changing the
reviewed host requires an explicit source change as well as build configuration.
Query parameters select a catalogue role; they never enable test mode or choose
a Firebase project. The existing local build still uses only
`MYDOXXX_TEST_LAB=true` and requires loopback.

## Parent-to-frame bridge

Before loading Flutter, the frame bridge defines:

```javascript
window.mydoxCloudTestLogin = async function(roleKey) {
  // Return JSON from the owner-authenticated portal broker.
  // projectId, databaseId, roleKey, role, uid, customToken
};
```

The parent must authenticate the authorized operator and obtain a custom token
for the exact registered frame/role. Both sides validate the exact message
origin, source window and per-request nonce/request ID. Respond only to the
requesting iframe. The parent operator's ID token never enters the Flutter
frame. Never put custom tokens in URLs, browser storage, logs, generated assets
or public configuration. Responses should be non-cacheable. The app expects a
JSON string, not a JavaScript object.

Initialize the portal operator's Firebase app with a separate name such as
`mydoxxx-cloud-owner`. Flutter uses `[DEFAULT]` in its role frames. Distinct app
names prevent the portal's persisted operator login from sharing an Auth
persistence key with the role frames before those frames select `NONE`.

Flutter checks the envelope's project, database, role key and exact synthetic UID
before custom-token sign-in. Auth persistence is `NONE`. It then checks the
signed `mydoxTest`, `testDatabase` and `role` claims and the synthetic profile.
Cloud sessions additionally require `cloudLab: true`, a nonempty
`labOperatorUid`, and integer `labExpiresAt` epoch milliseconds in the future
(8-hour broker lifetime, with 5 minutes maximum client clock tolerance).
The broker and Firestore rules must enforce authorization and expiry server-side;
these client checks are defence in depth, not a replacement for server checks.

The app does not receive stored test passwords. The existing local server's
email/password flow is unchanged. Cloud credential payloads are removed from the
working configuration after sign-in. Errors do not display bridge responses or
token contents.

## Unchanged testing limits

OTP `7777` is only the lab service-code generation value; existing expiry,
payment, timing, attendance and workflow checks still apply. Live SMS, payments,
push, media calls, uploads, external actions and real GPS remain disabled.
Cloud login support by itself is not evidence of deployment or successful
end-to-end multi-role browser testing; the verified deployment and remaining
browser checks are listed above.
