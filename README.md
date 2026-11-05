# MYDOXXX shared editable source

This is the shared editable source for both laptops: Flutter app, isolated
backend source, local test-room viewer and review notes. The ordinary source
folders were imported on 4 November 2026. The original source ZIPs and recovery
backend remain preserved. Local checkouts must retrieve source and rebuild;
local edits and old demo ZIPs do not auto-sync. Hosted testing can use the private
cloud site without a local build or the original PC.

Private repository: https://github.com/shrinath4all-del/MYDOXXX

| Item | What it shares |
|---|---|
| This editable repository | Source changes after a reviewed commit and push/pull |
| [Private cloud test room](https://mydoxxx-live-test.netlify.app/) | Static app updates after reviewed main merge, successful checks and Netlify deployment |
| Existing 20 MB private portable ZIP | One prebuilt demo snapshot; does not update itself |
| Firebase mydoxxx-dev-261102 / mydoxxx-testing | Existing shared synthetic test records |
| Backend deployment | A separate explicitly authorized operation; Git sync never deploys it |

Start with [SHARED-DEVELOPMENT.md](SHARED-DEVELOPMENT.md) and
[CODEX-HANDOFF.md](CODEX-HANDOFF.md). For hosted access and verification limits, read
[CLOUD-TEST-ROOM-HANDOFF.md](CLOUD-TEST-ROOM-HANDOFF.md). Run `python scripts/mydoxxx/dev-status.py`
to see this laptop's checked public target and Git version. It does not fetch or
connect to Firebase. A successful status check does not prove the remote is current.

Use **one Git root here**. `experiments/MYDOXXX/app` and `backend` are ordinary
subfolders, not separate repositories or submodules. Their historical source
commits remain provenance records; new edits use this root's shared commit.

No compiled build, test passwords, clinical data, service account, payment secret,
signing key or private runtime ZIP is included. Historical archives already in
the private GitHub repository should be preserved; use the ordinary source folders
for new development, rather than unpacking an old archive over them.
