# MYDOXXX experimental backend

This folder is the user-approved, isolated backend development source. Its scope
overrides the parent workspace's Antigravity source instruction only for this folder.

- Firebase project: `mydoxxx-dev-261102`, project number `724915428929`.
- Display name: MYDOXXX. Account for deployment: `shrinath4all@gmail.com`.
- Work here for experimental backend changes; the sibling `../app` is a separate
  Flutter repository and must not be overwritten by backend operations.
- Protected projects: `mydox-be432`, `mydox-shrinath-backup-261102`, `clinigo-77808`
  and the retired first setup project `mydoxxx`. Never deploy or mutate them.
- Keep source ZIPs and private recovery folders unchanged. Do not run their old
  seed/import/upload scripts against any cloud project while working here.
- This repository contains code and safe configuration only. Never add clinical
  records, user exports, service-account keys, live payment keys or backup ZIPs.
- All 36 handlers currently retain recovery guards. HTTP endpoints are private,
  schedules are staged as HTTP handlers, and client rules deny access. Do not imply
  that this is a production-ready or fully activated application backend.
- Before enabling side effects, use synthetic test identities/devices and Razorpay
  TEST credentials; review callable/scheduler metadata and authorization tests.
- Run `npm run verify` before committing. Use `scripts/deploy.ps1` with the explicit
  new-project target. Do not rely on a global Firebase project alias.
- Use Node.js 22 for dependency installation and cloud-runtime compatibility.

