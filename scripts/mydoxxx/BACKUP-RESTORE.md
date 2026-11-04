# MYDOXXX source backup and restore

This archive preserves the current experimental Flutter app, the guarded backend source, current handover notes, and explicitly reviewed local test-lab helpers. It is intended for the **private MYDOXXX repository in the Srinath GitHub account**.

The experimental Firebase project is **mydoxxx-dev-261102** (project number **724915428929**). The synthetic test database is **mydoxxx-testing**. Original IT, CliniGo and protected recovery backends remain separate. Do not change project IDs to point this experiment at a preserved backend.

## What is included

- `experiments/MYDOXXX/app/`: tracked Flutter source and assets, dependency lockfile, tests, and experimental client configuration.
- `experiments/MYDOXXX/backend/`: three guarded function groups, dependency lockfiles, deny-all default database/storage rules, target checks, and deployment helper.
- `docs/mydoxxx-experiment-2026-11-02/STATUS.md`: the current handover; check its date and stated limitations.
- `scripts/mydoxxx/`: the explicitly listed lab helpers and backup tools. Any local host helper supplied during packaging retains its original relative path.
- `SOURCE-MANIFEST.json`: exact source commits and SHA-256 hashes for every copied source file. The external `.zip.sha256` file verifies the whole archive.

Firebase client API keys in the three experimental SDK configuration files identify the client project; they are not service-account credentials. Access to data must still be controlled by Firebase Authentication and security rules.

## What is deliberately excluded

No clinical/patient records, Auth exports, database dumps, cloned Storage files, restore receipts, private test passwords, tokens, service-account keys, signing keystores, `key.properties`, Git internals/history, build output, dependency folders or logs are included. Binary PDFs/APKs and unrelated archives are not part of this code backup. Existing `.env` files are excluded except the backend's single safe `MYDOX_RECOVERY_MODE=true` flag.

This is a **code snapshot**, not a Firebase data backup or an APK. It does not transfer ownership or access to Google services. Keep the private recovery archives and app signing materials separately in their existing protected location. Never upload them to GitHub alongside this archive.

## Restore the code on another computer

1. Download the ZIP and its `.zip.sha256` companion. Compare the SHA-256 using `Get-FileHash -Algorithm SHA256 <filename>` on Windows, or `sha256sum <filename>` on Linux/macOS.
2. Extract `MYDOXXX` to a new workspace. Keep the internal directory structure intact; helpers expect `experiments/`, `scripts/` and `docs/` to share a workspace root. Do not extract over the protected original or the shared Antigravity source.
3. Read the app/backend `AGENTS.md` and `README.md` files and the dated handover before making changes. `SOURCE-MANIFEST.json` records which commits were packaged; generated archive files themselves are not listed in that manifest.
4. Install the tested Flutter/Dart version stated in the app handover. The current baseline uses Flutter **3.44.1**, Dart **3.12.1**. From `experiments/MYDOXXX/app`, run `flutter pub get`, then `flutter test` and an appropriate build. Android/iOS signing and distribution need their separate private setup; a Web build does not establish native release readiness.
5. Backend functions target Node **22**. From each `experiments/MYDOXXX/backend/functions/group-*` folder, run `npm ci` when needed. Read the backend README for isolation checks and deployment instructions. Keep recovery mode enabled while testing the copy.
6. If you want local version history, initialize a new Git repository for each source folder or commit this snapshot into the intended private repository. This ZIP does not contain prior `.git` history or authentication for either account.

## Test-lab access

Read `scripts/mydoxxx/TEST-LAB.md` and the local host helper's instructions. The Flutter lab uses a compile-time switch and loopback-only role panels. Each role uses a separate local origin and a server-supplied synthetic credential. Passwords are intentionally absent from this archive.

For a scheduled **Doctor** test, use the choices currently exposed in the app: **Clinic/Visit** or **Online**. A clinic appointment confirms immediately; it does not need a separate doctor acceptance. Check that the same booking appears in the Doctor panel, use the booking OTP at the permitted time to start and complete it, then verify a new chat message reaches the other role. Do not follow an older instruction to select a scheduled doctor home visit when that choice is absent. Nurse and Technician patient requests use their separate request inboxes and acceptance flow.

On the existing PC, the private credential/receipt files remain outside the repository. On another PC, arrange authorized local test credentials through the owner and existing test setup; do not copy passwords into Dart source, asset files, URLs or public Hosting. The recovery/setup helpers contain local Firebase CLI paths that may need an environment-specific update. Do not run recovery, seed or deployment commands blindly against a database that already contains data.

The synthetic test rules permit cooperation among approved test users. They are not production patient/provider permissions. Foreground request/chat updates are distinct from real FCM/SMS, Razorpay payouts and server automation. Original Cloud Functions remain private, guarded, and attached to the restored default database until deliberately reviewed and activated.

## Create the next source snapshot

Finish and commit all intended app/backend changes first. From the workspace root:

```text
python scripts/mydoxxx/package-source-backup.py --audit
python scripts/mydoxxx/package-source-backup.py
```

If a new reviewed local host file is outside the explicit default list, use `--extra-file relative/path/to/file` for both commands. The script scans source for common credential patterns, preserves byte contents, verifies file hashes inside the ZIP, and rejects a ZIP of 25,000,000 bytes or more. It makes no cloud calls or uploads, and changes neither app nor backend source. Pattern scanning reduces accidental disclosure; inspect the audit before sharing.
