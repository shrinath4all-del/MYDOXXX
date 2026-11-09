# Private cloud test-room rules

This directory is authorized for the separate MYDOXXX Netlify test room.
It overrides the parent CliniGo source instruction only for files here.

- Target only `mydoxxx-dev-261102` / named Standard database `mydoxxx-testing`.
- Preserve the exact 36 synthetic UID/role map and existing local test claims.
- The original projects, default database and Storage remain denied/protected.
- `verify-rules.cjs --remote` submits source to the Rules test API; it does not
  create a ruleset, release, database document, Auth user or deployment.
- Do not add production patient access or publish reusable test credentials.
- This minimal expiry policy does not provide immediate per-operator revocation.
