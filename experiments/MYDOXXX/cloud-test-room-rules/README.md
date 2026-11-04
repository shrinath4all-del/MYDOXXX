# Cloud role-session expiry

Target: `mydoxxx-dev-261102`, named Standard database `mydoxxx-testing` only.

This policy copies the existing exact 36-identity synthetic test allowlist and
adds an absolute expiry to cloud-issued role sessions. It does not grant access
to a Google owner identity, the preserved default database or Storage.

The token broker must include these additional signed claims:

| Claim | Required value |
|---|---|
| `cloudLab` | Boolean `true` |
| `labIssuedAt` | Integer epoch milliseconds, at or before request time |
| `labExpiresAt` | Integer epoch milliseconds, after request time |
| Maximum lifetime | `labExpiresAt - labIssuedAt <= 28,800,000` (8 hours) |

Local loopback/password logins with no `cloudLab` claim continue unchanged.
If `cloudLab` is present, false, malformed, missing-time, future-issued and
expired sessions fail closed. Firebase token refresh cannot move the original
signed expiry; a fresh authorized broker login is required for a new window.

Run `node experiments/MYDOXXX/cloud-test-room-rules/verify-rules.cjs` for offline
contract checks. Add `--remote` to compile and evaluate mocked requests using
Firebase Rules' test API. The runner checks the selected database edition and
asserts the deployed default and named rules releases are unchanged afterward.
No rule deployment occurs in the runner.

The existing policy is cooperative synthetic testing: every allowed role can
read/write all records in this named database. It is not production role-level
authorization. No real patient data belongs here.

Removing an operator from the broker allowlist blocks new tokens, but already
issued cloud sessions can retain access until their absolute expiry (at most
8 hours). Portal logout removes that browser's role sessions, not a stolen token.
Immediate per-operator server revocation is not implemented by this policy.
Revoking a shared role UID also affects other laptops using that identity.

Reference: https://firebase.google.com/docs/auth/admin/manage-sessions
