# Codex handoff: run the private MyDox test room

Read AGENTS.md first. This is a portable runtime kit, not a development repository or database backup. The app is already built. Start the existing demo; do not recreate it.

## Exact target

- Firebase project: `mydoxxx-dev-261102`, number `724915428929`.
- Named synthetic database: `mydoxxx-testing`.
- 36 synthetic identities: three in each of 12 families. Cardiologist display names retain `doctor`, `doctor_2`, `doctor_3` keys.
- Never select or modify `mydox-be432`, `mydox-shrinath-backup-261102`, `clinigo-77808`, retired `mydoxxx`, or the target's restored `(default)` database.

## Run without setup

1. Discover an existing Python **3.10+** using `py -3`, `python3`, `python`, or an available Codex-bundled runtime. Do not assume any original Lenovo path exists. Do not automatically install Python or dependencies.
2. From this extracted folder run `<python> start.py --check`. It validates file hashes, the exact isolated project/database/account set and all 37 local ports. It starts no server/browser and makes no cloud requests. Never print credential contents.
3. If checks pass, run `<python> start.py --no-browser` and keep its process alive. Open the printed URL using the user's browser/computer tools. Default is `http://127.0.0.1:8889/`.
4. If ports are occupied, use `--port 8989 --role-port 8991` for both check and launch. Preserve existing servers. The launcher passes absolute paths derived from its own folder to the host's `--build` and `--credentials` arguments.
5. The default four-screen layout is available immediately. Click **Emergency team**, choose **Columns 4**, then collapse **Choose accounts** for Patient 1/Hospital 1/Cardiologist 1/Ambulance 1. Select other people using the account picker, without reloading peers. Do not claim a complete medical/emergency workflow has passed merely because a screen loads.

The Windows START-MYDOXXX.cmd launcher starts Python and opens the browser automatically. Python standard-library modules are sufficient; no Flutter SDK, Node, Firebase CLI, service account or owner Google login is required.

## Private/runtime boundaries

`private/test-lab-credentials.json` is deliberately **outside** the served `build/` and `server/` folders. The host exposes only the assigned account through a guarded same-origin endpoint; there is no all-credentials endpoint. It binds to 127.0.0.1 only. Do not expose it over LAN, tunnels, public hosting or firewall changes.

`RUNTIME-MANIFEST.json` records hashes and source provenance. The manifest and external ZIP hash detect accidental corruption, not a cryptographic signature. Private credentials are included only in this private runtime kit; no Auth exports, clinical records, restore receipts, admin tokens, signing keys or Firebase-owner credentials are supplied.

Dummy **booking / duty OTP7777** belongs only to the test service flow; it is not a sign-in/SMS bypass. Existing validators retain timing, status, payment, assignment and expiry checks. The normal app build is separate. A read-only migration verified existing synthetic codes, but live OTP entry/completion is not claimed by this handoff.

Internet is required. These are shared live synthetic Firebase records, so browser test actions are visible to the other laptop. Conversation sync does not transfer local files or browser storage. The prebuilt app, private credentials and folder must be transferred together.

Once this kit is running on the second laptop, the original PC can be turned off. The second laptop needs its own internet connection; its local browser layout is saved separately while Firebase test data is shared.
