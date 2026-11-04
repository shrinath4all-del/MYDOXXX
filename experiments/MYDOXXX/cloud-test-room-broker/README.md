# MYDOXXX cloud test-room role-token broker

Prepared source only. No deployment, IAM/provider changes, user creation or database
writes were performed by this implementation. This is a separate Functions
codebase; it does not edit or activate the 36 recovered business handlers.

## Interface

Export: `mintMyDoxLabRole`, HTTPS function in `us-central1`, Node22.

```http
POST <deployed-broker-url>/
Origin: https://mydoxxx-live-test.netlify.app
Content-Type: application/json
Authorization: Bearer <owner's Firebase ID token from Google sign-in>

{"roleKey":"doctor_2"}
```

Successful JSON contains `customToken`, `projectId`, `databaseId`, `roleKey`, `role`,
`uid`, `labIssuedAt` and `labExpiresAt`. The frontend exchanges the custom token
using Firebase `signInWithCustomToken()` in that role's isolated Auth instance.
Never put owner/custom/ID/refresh tokens in URLs, logs, analytics or shared storage.
Do not forward the owner token into role iframes. Keep role auth in memory, close
and sign out panels when the owner signs out, and obtain each token only when
opening its selected panel. Use the deployed endpoint URL, not a guessed address.

Only verified Google sign-in as **shrinath4all@gmail.com** is allowed. An ID token
from password/custom/anonymous sign-in, another project/tenant, a changed current
owner profile or any other email fails closed. Admin `verifyIdToken(token, true)`
checks signature/expiry/revocation; the current owner record must also be enabled,
verified and linked to that Google identity.

The request accepts only one catalogue `roleKey`; the server supplies the fixed
UID and role. All 36 users must already exist, be enabled and retain exactly the
seeded `mydoxTest`, `testDatabase`, `role` claims. Arbitrary UIDs, claims or owner
lists cannot be supplied. No `setCustomUserClaims`, user creation, password change,
Firestore access or credential-file reading occurs.

JSON is limited to 512 bytes, bearer token to 8192 bytes; wrong content types,
duplicate security headers, query/path variations and unsupported encodings fail.
CORS permits the exact HTTPS origin in `MYDOX_CLOUD_ORIGIN`, without wildcard or
cookie credentials. Origin is browser protection, not authentication: every POST
still requires the owner's valid token. Errors contain only fixed codes. Every
response is no-store. Invalid origin receives no CORS grant.

## Cloud-session claims and lifetime

Each issued custom token contains:

```text
mydoxTest = true
testDatabase = mydoxxx-testing
role = mapped fixed role
cloudLab = true
labOperatorUid = verified owner's UID
labIssuedAt = server Date.now() as integer epoch milliseconds
labExpiresAt = labIssuedAt + 28,800,000 milliseconds (8 hours)
```

These are token claims only; the underlying user's stored custom claims are not
changed. This allows the existing local password-based lab to remain distinct.

**The eight-hour deadline must be enforced in the separately reviewed named-DB
rules before enabling cloud testing.** Rules should require integer timestamps,
issued-at no later than request time, expiry after request time, a maximum
eight-hour interval, and a valid operator identifier for `cloudLab` tokens. The
broker itself does not deploy those rules.

Firebase custom sign-in tokens have their own exchange validity, and exchanging
one yields a refreshable Firebase session. That exchange-token lifetime does not
automatically end the resulting role session. The fixed `labExpiresAt` rule check
is what blocks cloud database access after eight hours, including refreshed ID
tokens. The owner can request a fresh eight-hour grant through the broker while
still authorized.

There is no server-side operator access document or per-grant logout endpoint in
this initial version. Frontend logout signs out/closes current panels, but is not
immediate revocation of copied role tokens elsewhere. Revoking the owner's tokens
blocks future broker grants; already issued role grants remain subject to their
eight-hour deadline. Admin revocation/disable of a synthetic role UID affects
other sessions for the same role, including the local test lab. Account revocation
and emergency containment require a separately reviewed owner action.

## Dedicated runtime identity and minimum access

The runtime identity is fixed:

`mydoxxx-lab-broker@mydoxxx-dev-261102.iam.gserviceaccount.com`

Use Google-managed signing with Application Default Credentials. Do not create or
download a service-account key. The code explicitly selects this signer/project;
runtime project variables must match `mydoxxx-dev-261102`, and Auth emulator mode
is refused. The broker has no Firestore, Storage, Secret Manager or billing client.

The owner/deployer must separately create/configure this dedicated service account:

1. Project-scoped read permission `firebaseauth.users.get` for revocation/current
   owner and synthetic-user checks. `iam/auth-read-role.json` supplies a custom-role
   definition for that permission alone. The broader predefined
   `roles/firebaseauth.viewer` is a fallback if custom roles are unavailable; it
   must not be replaced with Auth Admin, Editor or Owner.
2. `iam.serviceAccounts.signBlob` on **this service-account resource only**, granted
   to the same runtime identity. `iam/self-sign-role.json` is a custom-role
   definition. The predefined `roles/iam.serviceAccountTokenCreator` scoped to this
   single service account is an alternative, with additional signing/token powers.
   Do not grant Token Creator across the project or on owner/other service accounts.
3. IAM Credentials signing API and normal Cloud Functions build/runtime APIs must
   be available. Deployer/build identities need their normal deployment permissions
   and permission to act as this runtime account; do not give those permissions to
   the runtime identity as a convenience.
4. Enable/configure Google sign-in and the exact frontend authorized domain only
   through the owner's separately approved setup. This package has no `auth`, rules,
   storage or hosting section, and never initializes Identity Platform.

HTTP invocation is publicly reachable at the transport layer (`invoker: public`)
because browser Firebase ID tokens are verified by this function, not Cloud Run
IAM. This is a deliberate difference from the private recovered functions. It does
not grant anonymous role tokens: all POSTs pass the owner checks. OPTIONS returns
only the exact CORS policy. Runtime min0/max1, 256MiB, concurrency10 and timeout30s
limit the deployment footprint; they are not a durable per-user rate limiter.

## Tests and later deployment

The separate owner-operated IAM helper uses the existing workspace's target- and
owner-guarded `scripts/mydoxxx/common.cjs`. It is excluded from deployment. From the
workspace root, inspect without creating resources or enabling APIs:

```text
node experiments/MYDOXXX/cloud-test-room-broker/setup-iam.cjs --check
```

No flag also means read-only. After review/authorization, the owner may run:

```text
node experiments/MYDOXXX/cloud-test-room-broker/setup-iam.cjs --apply
```

Apply creates only the dedicated account, two exact custom roles, the Auth-read
project binding to that account, its self-scoped signBlob binding, and enables the
IAM Credentials API if needed. Existing policy members, conditional grants,
auditConfigs and etags are preserved. Changed/conflicting roles, unexpected broker
project permissions or concurrent policy edits stop the operation; no broad role
fallback, blind replacement or automatic privilege expansion occurs. It does not
grant deployment rights, alter Google sign-in, set function public invocation,
deploy functions or change rules. Re-run `--check` to inspect propagation. This
helper depends on the existing owner's local Firebase CLI login and is not part
of the public frontend or a general cross-machine authentication mechanism.

`npm test` runs built-in Node tests with fake Auth operations: no SDK install,
network, cloud mutation or secrets are needed. It checks all 36 role mappings,
owner/provider/project/revocation policy, current owner and target records, claims,
eight-hour timestamps, input/CORS limits and sanitized errors. A lockfile reuses
the reviewed dependency versions already present in the experiment: Admin12.7.0
and Functions6.6.0. Dependency installation is separate from the offline tests.

Only after owner approval and independent review, the deployer can install locked
dependencies and deploy **this codebase only**, from this directory:

```text
npm ci --ignore-scripts --no-audit --no-fund
npm test
firebase deploy --only functions:mydoxxx-cloud-lab-broker --project mydoxxx-dev-261102 --account shrinath4all@gmail.com
```

Do not run a broad functions deployment from the recovered backend or change its
Firebase configuration. Verify dedicated runtime identity, exact origin, owner
Google sign-in and denied non-owner requests after deployment. Then verify one
actual existing role login, cloud expiry-rule behavior and logout-panel cleanup.
Offline policy tests do not establish those live integration results.

## Primary references

- [Firebase ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Firebase session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions)
- [Custom tokens and managed signing](https://firebase.google.com/docs/auth/admin/create-custom-tokens)
- [Auth IAM permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firebaseauth)
- [Dedicated function service accounts](https://firebase.google.com/docs/functions/manage-functions#set_a_service_account)
