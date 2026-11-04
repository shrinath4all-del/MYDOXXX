# Private portable MYDOXXX runtime

The user's authorized task here is to launch the existing test room on this laptop. Preserve the kit's app, backend target, test accounts and shared data.

- Read START-HERE.md and CODEX-HANDOFF.md. Use `start.py --check`, then `start.py`; all paths are relative to the extracted kit.
- Use an existing Python 3.10+ runtime. Do not assume an absolute path from another PC. Do not install packages/SDKs automatically. No Flutter, Node, Firebase CLI or Google-owner login is needed.
- Never print, upload, commit or attach `private/test-lab-credentials.json`, its contents, or the whole private runtime ZIP. Keep credentials outside served folders. Do not initialize a Git repository in this kit or defeat its .gitignore.
- Never seed/reset accounts, reset passwords, change Auth providers, write rules/indexes, change billing, deploy Functions/Hosting, or modify default/restored/original backends merely to run the demo. Ask the owner for a refreshed kit if access fails.
- Do not run recovery/maintenance scripts copied from another project. None is required by this kit.
- Keep 127.0.0.1 binding, guarded credential endpoints and CPU-rendering bootstrap behavior. Do not expose a LAN address, tunnel, public website or permissive CORS.
- Use alternate local ports if busy; never kill unrelated apps or the other test room. Use --no-browser when browser opening is handled separately. Stop only the child/server started for this kit.
- Open four selected screens initially; do not load all36 without user intent. All interfaces share the existing synthetic database, so do not reset data for a clean-looking presentation.
- Test booking/duty OTP7777 is not an Authentication/SMS code. Do not bypass timing, status, payment, assignment or expiry checks.
- A successful local startup is not proof that all clinical workflows, payments, FCM or a production release work. Report only checks actually observed.
