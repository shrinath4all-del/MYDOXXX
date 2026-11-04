# Codex handoff: shared editable MYDOXXX source

Read root AGENTS.md and SHARED-DEVELOPMENT.md first. This is the user's independent
experimental app, not the original CliniGo source or the private demo ZIP.

1. Confirm that the owner/publishing agent has completed the ordinary-source import
   to private `https://github.com/shrinath4all-del/MYDOXXX`. Clone into a new short
   local folder using approved Git authentication. Do not overwrite existing work.
   GitHub connector authorization does not itself configure terminal Git.
2. Select the repository root in Codex. Run `scripts/mydoxxx/dev-status.py` using an
   available Python3.10+ (py -3 / python3 / python / bundled runtime). Confirm a single
   Git root and exact project/database. Do not rely on the old source commit IDs
   as the new monorepo version. Do not install tools without explicit authorization.
3. Locate Flutter. Privately copy the owner's existing test credential JSON from
   the runtime kit into the ignored path in SHARED-DEVELOPMENT.md; never print it.
   Do not seed/reset Firebase or create replacement accounts.
4. Resolve existing dependencies, build `MYDOXXX_TEST_LAB=true`, and run the supplied
   loopback server with explicit relative build/credential paths. Do not deploy.
5. Open the console; select Emergency team, Columns4, collapse Choose accounts.
   Explain that test records are shared, while source updates require commit/push/
   pull and a rebuild on each laptop. Test booking/duty OTP7777 is not login OTP.
6. For a new code task, inspect status, update only a clean branch with --ff-only,
   create a task branch, test changes, review staged files, then use an approved
   authenticated branch/PR workflow. Do not extract or save connector tokens.

Suggested owner prompt after the source import is confirmed:

> Read AGENTS.md and CODEX-HANDOFF.md in this MYDOXXX clone. Check its Git version
> and exact synthetic Firebase target. Use the privately copied test credentials,
> rebuild the local test app, and open four phones using Emergency team and Columns4.
> Keep the existing Firebase configuration and records unchanged. For edits, use a
> separate task branch and tell me the commit after tests pass.
