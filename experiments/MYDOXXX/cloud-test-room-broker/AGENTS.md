# Dedicated MYDOXXX cloud test-room broker

This source is separate from recovered functions. Use only project
`mydoxxx-dev-261102` and named synthetic database `mydoxxx-testing`.

- Code/test work does not authorize deployment, IAM changes, provider setup, user
  creation, record writes, or rules changes. Root/owner handles those separately.
- No Firebase passwords, service-account keys or tokens belong here or in logs.
- Only verified Google `shrinath4all@gmail.com` may obtain a fixed existing test
  role. Never broaden the owner allowlist or accept arbitrary UIDs/claims.
- Preserve token revocation checks, exact Origin, JSON limits and no-store headers.
- Run `npm test`; tests use a fake Auth adapter and perform no cloud calls.
- Runtime index/handler/policy must not import common.cjs recovery/session helpers.
  The separate owner-operated setup-iam.cjs uses its guarded session only; it is
  excluded from function deployment and defaults to read-only inspection. Its
  explicit --apply needs the owner's separately authorized deployment setup.
