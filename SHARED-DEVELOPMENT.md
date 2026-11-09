# Shared development on two laptops

## State of this handoff

The owner connected the Srinath GitHub account, and ordinary editable source was
added on 4 November 2026 while preserving the existing archive files and history.
Use this repository for shared development. Local development on either laptop
needs its own checkout and rebuilt app. Merely opening the old portable ZIP does
not retrieve new source.
The original PC must explicitly select its shared checkout before new development.

The app snapshot came from `57379575165107f3fe93228ce7a53287df445627`; backend
source came from `f21181037c1bba645f623af38f34110b438b0125`. These old separate-repo
commit IDs are provenance, not the future root Git commit. No Git history or `.git`
folder is embedded in this prepared tree. After publication, use the root commit
reported by dev-status to compare laptops.

## Hosted testing from either laptop

Open **https://mydoxxx-live-test.netlify.app/** for the no-login, browser-local
sample demonstration. Its changes reset on reload and never reach Firebase.
For the shared synthetic test room, use **/private.html** on that site and the
approved Google operator login. Neither route needs the original PC running or
copied test passwords. Production public access is enabled only after the
reviewed demo package is published and the owner-authorized Netlify visitor-gate
change is verified. See
[CLOUD-TEST-ROOM-HANDOFF.md](CLOUD-TEST-ROOM-HANDOFF.md) for access and verification limits.

Codex and Claude edit unique task branches in this same repository. A reviewed
merge to main runs **Cloud lab checks** and Netlify's native build, then updates
the static hosted app on success. Confirm the published commit before reloading
panels. Local builds and portable ZIPs remain separate snapshots. Shared Firebase
test records can be affected by either laptop; use only fictional information.

## Optional local development/test setup on a laptop

1. Authenticate Git to the private `shrinath4all-del/MYDOXXX` repository with the
   owner's approved method. Connected GitHub plugin access does not automatically
   authenticate terminal Git. Do not place access tokens in files or commands.
2. Once ordinary-source publication is confirmed, clone into a short new local
   folder. Do not clone over the portable runtime kit or an existing dirty source:

   ```text
   git clone https://github.com/shrinath4all-del/MYDOXXX.git
   cd MYDOXXX
   python scripts/mydoxxx/dev-status.py
   ```

3. Open this repository root as the Codex local project and read AGENTS.md. Both
   app and backend are normal directories under this single root. No extra Git
   initialization is needed. A source archive download without `.git` is a snapshot,
   not a working synchronized checkout; dev-status identifies that distinction.
4. Locate installed Python3.10+ and Flutter/Dart. Source snapshot verification used
   Flutter3.44.1 / Dart3.12.1. Use compatible tools and the lockfile; do not upgrade
   dependencies implicitly. Unlike the prebuilt demo ZIP, editing/rebuilding the
   Flutter source needs a Flutter SDK. Do not install tools automatically.
5. Privately copy only `private/test-lab-credentials.json` from the owner's extracted
   portable runtime kit into this clone's ignored
   `private-backups/mydoxxx-dev-261102/test-lab-credentials.json`. Create the parent
   directory if needed. Never print or add this JSON to Git. Reuse existing accounts;
   do not seed users, reset passwords, change Auth providers or restore Firebase.
6. In `experiments/MYDOXXX/app`, resolve the existing lockfile dependencies once,
   then rebuild this source as the local lab (dependency download needs internet):

   ```text
   flutter pub get
   flutter build web --release --no-pub --dart-define=MYDOXXX_TEST_LAB=true --output=build/web-lab
   ```

   Review any lockfile changes before committing. Do not use `flutter pub upgrade`
   as routine setup. From the repository root start the existing loopback host:

   ```text
   python scripts/mydoxxx/serve-test-lab.py --build experiments/MYDOXXX/app/build/web-lab --credentials private-backups/mydoxxx-dev-261102/test-lab-credentials.json
   ```

7. Open `http://127.0.0.1:8889/`, choose **Emergency team**, **Columns4**, and collapse
   **Choose accounts**. Patient1, Hospital1, Cardiologist1 and Ambulance1 appear.
   Default role ports8891–8926 must be available. If occupied, preserve the running
   app and append `--port 8989 --role-port 8991` to use console8989/roles8991–9026.
   The Python host uses stdlib only; no Firebase-owner sign-in or Firebase CLI is
   required merely to run the synthetic test room. Internet is required for Firebase.

`7777` is the **test booking/duty OTP**, not Firebase/SMS sign-in. Existing service
timing, payment, assignment, expiry and other checks remain. Browser tests change
shared synthetic records and can affect the other laptop's test scenario. Use only
fictional information. The original PC need not remain running once the second
laptop has its own source/build/credentials and internet access.

## Daily source workflow

Before editing, from the single repository root:

```text
python scripts/mydoxxx/dev-status.py
git status --short
# Continue only after existing edits are safely committed/handled:
git switch main
git pull --ff-only
git switch -c codex/laptop2-descriptive-task
```

Use a unique branch per task/laptop; do not have two machines silently edit the
same task branch. Make a small change in the appropriate subfolder, run the
relevant tests, rebuild the lab, review `git diff`, and commit only intended source.
Do not `git add .` blindly: ignored private directories are a backstop, not a
substitute for reviewing staged files. Share the task branch and PR:

```text
git push -u origin codex/laptop2-descriptive-task
```

Merge reviewed work, then on the other clean laptop `git switch main` followed by
`git pull --ff-only`. Rebuild there and reload local app panels so they execute the
new build. Git changes do not update an already-open browser, compiled build or
old portable ZIP. Show dev-status on both laptops and compare commits; its local
read-only check does not contact GitHub or prove either checkout is up to date.
If fast-forward fails, stop and inspect divergence; never force/reset/discard work.

If only the GitHub connector is authenticated, it can perform explicitly scoped
repository reads and branch/PR writes. Do not assume terminal `git pull/push` will
work, do not harvest connector credentials, and do not claim cross-laptop source
sync until each checkout can receive the published commit through an approved
authenticated path. An agent using GitHub Git Data APIs must preserve the existing
tree and commit parent; it must not replace the repository with only its task files.

## Local checks and deployment boundaries

- Run app tests appropriate to the change from the app subfolder. Viewer tests:
  `python scripts/mydoxxx/test_serve_test_lab.py` and
  `node --test scripts/mydoxxx/test-console.test.cjs` from the root.
- The backend is source-only. Node22 and its locked dependencies are required for
  its local tests. Installing/testing it is separate from deploying it. Do not
  run its deploy helper merely to open a test room.
- Source uses exact project `mydoxxx-dev-261102`, project number `724915428929`,
  synthetic database `mydoxxx-testing`; restored `(default)` remains protected.
  Existing recovered functions do not process the named synthetic database.
- Do not run legacy prepare/expand/OTP migrations again. They already ran in the
  shared lab and are retained for reviewed recovery reference only.
- The old workspace-specific `package-source-backup.py` is intentionally omitted:
  it assumed two nested Git repositories. Use the single Git root for source
  history; never run the old script against an arbitrary ancestor workspace.
- Public portable templates and `package-portable-test-room.py` are included for
  future **owner-private** demo packaging. That builder requires a real clean root
  checkout, a validated rebuilt lab with matching validation-receipt hash, and the
  privately supplied test credentials. Its output is credential-bearing and must
  stay ignored/local; it is not a source backup or automatic delivery system.

The existing 20 MB demo kit is useful for presentations without Flutter. This source
tree is for edits. Firebase shares test data. Git shares reviewed source. Deployment
of the static hosted test room follows an approved main merge and successful
checks. Backend/Firebase deployment remains a separate explicitly authorized action.

