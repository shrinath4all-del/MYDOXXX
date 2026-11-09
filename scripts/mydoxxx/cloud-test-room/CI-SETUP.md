# Approved-branch cloud test-site updates

This configuration is for **shrinath4all-del/MYDOXXX** and the existing private
**https://mydoxxx-live-test.netlify.app/** site. It does not update the older
`mydoxxxx.netlify.app` app, change Firebase, or publish a second site.

## Reviewed release path

1. The reviewed cloud source and CI configuration are published in the
   shared repository. Root files are `netlify.toml` and
   `.github/workflows/mydox-cloud-checks.yml`; the build script is
   `scripts/mydoxxx/cloud-test-room/ci-build.sh`. The cloud packager and its
   `test_package_site.py` must be included in the same change.
2. Use a task branch and a pull request into **main**. Require approval and the
   **Cloud lab checks** GitHub check before merging; disallow force pushes.
   Branch protection must be set in GitHub separately. A workflow file alone
   does not stop somebody from pushing unreviewed code directly to main.
3. The existing Netlify test site is linked to this private GitHub repository,
   with **main** as the production branch and repository root as its base.
   Native Git integration supplies the checkout; no Netlify API token, Firebase
   service-account key, private test password or owner token belongs in CI.
4. Preserve Netlify's **kunal110284 team-only visitor access**. Retain the portal's
   Google operator allowlist. Disable deploy previews and other branch deploys.
   This configuration also skips them and refuses nonproduction/non-main builds.
5. A reviewed merge to main triggers Netlify's own build. It repeats the checks,
   compiles Flutter, packages only static allowlisted files, then publishes
   `dist/cloud-test-room` if every step succeeds. A failed build does not replace
   the successful deployed version. Verify each published source commit and
   check both access layers when testing a new release.

## Build safeguards

- Flutter **3.44.1**, official Git revision
  `924134a44c189315be2148659913dda1671cbe99`; Dart **3.12.1**. The tag, official
  remote, checkout cleanliness and framework metadata are checked. No Flutter
  upgrade command is used. Dependencies must satisfy the committed lockfile.
- Linux x86_64, Node **22**, Python **3.11+**. GitHub Actions are pinned by full
  upstream commit IDs. Linux test runners need `libglu1-mesa`.
  Netlify documents Ubuntu 24.04 but does not enumerate every graphics library;
  the script checks the downloaded test runtime with `ldd` and fails with missing
  library names before tests. It does not attempt privileged installs on Netlify.
- Checks: viewer/catalogue/bridge tests, broker and IAM-policy unit tests,
  offline rules-contract assertions, Python packager tests, focused Flutter
  analysis, the login/isolation suite and the India-clock guard tests in normal/local/cloud modes.
  Test counts can change when reviewed tests are added; CI trusts the test exit
  status rather than a fixed count.
- The final build enables only the explicit cloud lab flags and `/panel/` base
  path at the exact approved HTTPS origin. CI packaging does not need or read the
  owner's private passwords: it uses the reviewed high-entropy fingerprints and
  strict artifact allowlist. Credential rotation requires a reviewed fingerprint
  update. Local default packaging still checks the actual private 36 passwords.
  A fresh `dist/cloud-test-room` directory is required.
- An explicitly empty `.netlify/no-functions` directory prevents accidental
  Netlify Functions discovery. No Firebase CLI, seed, Auth setup, rule deployment,
  broker deployment, IAM operation or authenticated live test runs in this build.
  Offline rules checks prepare mocked cases; they do not repeat remote rule tests.

For a GitHub/local Linux check only:

```sh
bash scripts/mydoxxx/cloud-test-room/ci-build.sh --check
```

Netlify uses `--netlify` and additionally validates its production context, main
branch, exact primary site URL and repository URL. `--validate-context` checks
that gate without building or contacting any cloud service. Keep shell files LF.

## Integration status

On 5 November 2026, the existing private test site was linked to
`shrinath4all-del/MYDOXXX` using a repository-only, read-only deploy key and an
active push-only webhook. The webhook uses JSON with SSL verification enabled;
GitHub's initial ping succeeded. Netlify CLI confirmed CI/CD configuration.
Production remains `main`; Netlify team-only access and the portal's Google
operator allowlist remain in place.

On 5 November 2026, a native GitHub-triggered Netlify build successfully published
main commit `d585896db57de2178de04821689c00cb97514afe` as deployment
`6aec447735617a4fec132438`. The triggering source commit and the site's published
deployment pointer were verified. Reviewed main merges now automatically build,
test and publish the static test room. This verifies the delivery pipeline;
operator sign-in and multi-role workflows still need separate browser evidence.

Netlify secret scanning remains enabled. One separately reviewed, site-specific
production-build exception covers one exact public Firebase Android client
identifier. No paths or credential classes are excluded. Do not broaden that
exception or disable scanning to resolve a future finding without review.

Branch protection and required-review enforcement remain unconfigured. Changes
from Codex or Claude should use a task branch, pass **Cloud lab checks**, and be
reviewed before merging to `main`. Neither the Git connection nor this document
enforces those reviews.

Official references:
- https://github.com/flutter/flutter/releases/tag/3.44.1
- https://docs.netlify.com/build/configure-builds/file-based-configuration/
- https://docs.netlify.com/build/configure-builds/manage-dependencies/
