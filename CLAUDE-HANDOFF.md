# Continue MYDOXXX in the existing Claude Code cloud session

The objective is parallel development of the **same Flutter/Firebase app** with
Codex and the owner's laptops. Keep Claude's work and integrate the newer shared
source; do not start another app or another Firebase backend.

## 1. Preserve the existing Claude work

The existing session reports branch `claude/development-session-92q2g1`, commit
`9f5d0a9`, an older archive import and a timezone fix. These are handoff references,
not independently verified Git facts. Inspect the actual checkout first:

```text
git remote -v
git status --short
git branch --show-current
git log --oneline --decorate -8
```

Confirm the intended private remote is `shrinath4all-del/MYDOXXX`. If the checkout
contains unfinished edits, preserve them and explain which belong to this task;
do not switch branches, stash, reset or commit unrelated work just to make it clean.
Review the timezone fix and retain its intended behavior when integrating main.

Once the task branch is clean and ordinary-source publication on main is confirmed:

```text
git fetch origin
git log --oneline HEAD..origin/main
git diff --stat HEAD...origin/main
# Remain on the existing Claude task branch, not main:
git merge origin/main
```

Before merging, check that `origin/main` contains root `AGENTS.md`,
`SHARED-DEVELOPMENT.md` and the ordinary app/backend directories below. If main
still contains only ZIP archives, wait for the publishing agent's verified source
commit. Do not unpack old archives over the working tree to compensate.

This merge preserves both histories and must not force-push or discard Claude's
commit. Resolve conflicts file by file, coordinating with Codex on overlapping
Flutter/helper changes. Preserve required current guards, role identities and
timezone behavior. Do not use broad `ours`/`theirs`, automatic rebases, or
`--allow-unrelated-histories`; report unexpected history/layout conflicts first.

## 2. Use the shared source and backend

| Location | Purpose |
|---|---|
| `experiments/MYDOXXX/app` | Editable Flutter app and its tests |
| `experiments/MYDOXXX/backend` | Guarded recovered backend source and local tests |
| `scripts/mydoxxx` | Local multi-role viewer, checks and reviewed historical helpers |
| `docs/` | Handover and recorded verification evidence |
| `private-backups/` | Ignored owner-private local files; never committed |

There is one Git repository at the root; app and backend are normal subfolders.
Historical source commit IDs in manifests identify their earlier snapshots, not
the current monorepo commit. Run from the root:

```text
python scripts/mydoxxx/dev-status.py
```

The required public configuration is already included:

- Firebase project **`mydoxxx-dev-261102`**, number **`724915428929`**.
- Shared synthetic named database **`mydoxxx-testing`**.
- **36 existing accounts:** Patient, Doctor/Cardiologist, Nurse, Hospital,
  Ambulance, Care Physician, Technician, Therapist, Care Agency, Nursing Agency,
  Technician Agency and Physio Agency — three accounts per family.
- Keep all keys, UIDs and existing role port mappings. Cardiologist display names
  use the original `doctor` role keys. The preserved default database and other
  projects are outside this coding task.

Private test credentials are **not** available from GitHub. On the owner's local
machine they are supplied privately at
`private-backups/mydoxxx-dev-261102/test-lab-credentials.json`. Do not print them,
request public upload, embed them in code, or generate new accounts. Cloud coding
and offline tests can continue without them. Firebase-owner login is not required
for source edits or a Flutter build.

## 3. Validate the actual changes

Read the root instructions and app scenario guide before editing. Locate existing
tools; the reviewed source used **Flutter3.44.1/Dart3.12.1**, Python3.10+ for the
viewer and Node22 for backend development. Do not assume Lenovo-specific paths
exist in Claude's cloud environment, or install/upgrade tools automatically.

From the app directory, if dependencies are not already available, use the existing
lockfile with `flutter pub get`; review resulting lockfile changes. Then run the
tests relevant to the change and rebuild the lab:

```text
flutter test --no-pub <relevant-test-file-or-directory>
flutter build web --release --no-pub --dart-define=MYDOXXX_TEST_LAB=true --output=build/web-lab
```

Replace the test placeholder with real changed-area tests. Viewer-only checks run
from the repository root:

```text
python scripts/mydoxxx/test_serve_test_lab.py
node --test scripts/mydoxxx/test-console.test.cjs
```

If Flutter, dependencies, credentials or required network access are unavailable,
state exactly which checks could and could not run. Continue useful source review
and available offline checks; do not bypass target guards, fake test success,
activate Auth, modify security rules or substitute a different backend.

The local 36-role viewer uses real synthetic Firebase records; it is not a static
mock. `7777` is **test booking/duty OTP**, not SMS sign-in. Booked time, status,
payment, expiry and assignment validation still apply. Existing guarded Cloud
Functions do not process the named test database; no production privacy, payment,
background-push or medical-readiness claim follows from a successful UI test.

## 4. Share work without overwriting the other developer

Finish the integration/current task on its preserved Claude branch. For subsequent
tasks, start a new descriptive `claude/<task>` branch from a clean, updated main.
Coordinate files before both agents edit the same area. Review the diff and stage
only intended source; private archives, credentials, builds and logs stay ignored.
Commit, push the task branch and open a PR into main through the authorized GitHub
workflow. Include the exact commit, behavior change, test results and limitations.

After a reviewed merge, each laptop pulls the source and rebuilds its own app.
The old private 20 MB portable demo remains a fixed compiled snapshot. Chat history,
GitHub source, local browser layout and Firebase test records do not automatically
synchronize with one another. Backend deployment remains a separate explicit task.

Do not expose the credential-bearing localhost viewer through a cloud preview,
tunnel or public deployment. To present four phones, use the owner's private local
runtime/source setup, select **Emergency team**, **Columns4**, then collapse
**Choose accounts**. A cloud build can be reviewed without publishing its test logins.

## Prompt for the existing Claude session

> Read CLAUDE.md, CLAUDE-HANDOFF.md and the root development instructions. Verify and
> preserve my existing Claude branch and timezone fix. Fetch and review the verified
> latest shared main, then merge it into this branch without force/reset or dropping
> either developer's changes. Continue the same Flutter/Firebase app using the exact
> MYDOXXX synthetic backend. Tell me the resulting commit, what you changed and
> which tests actually passed. Do not seed, deploy, change Auth/security/billing,
> expose private test credentials, or switch frameworks/backends.
