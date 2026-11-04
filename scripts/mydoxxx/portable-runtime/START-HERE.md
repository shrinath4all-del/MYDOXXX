# MyDox private portable test room

This kit opens the existing MyDox demonstration on your own second laptop. It contains the ready-built app and **36 private synthetic test logins**. Keep the whole ZIP/folder private; it is not an investor handout, public website or source-code GitHub upload.

## Move and open it

1. Copy the private ZIP to your other laptop using USB or a private transfer. Extract the entire ZIP to a short ordinary local folder, such as Documents/MyDoxTestRoom, to avoid Windows extraction path limits. Do not run it inside the ZIP preview.
2. The laptop needs **Python 3.10 or newer**, a modern browser and internet access. Flutter, Node, Firebase CLI and a Google/Firebase-owner login are not needed. Nothing is installed automatically.
3. On Windows, double-click **START-MYDOXXX.cmd**. Keep the launcher window open. It validates the kit, starts only local servers, then opens **http://127.0.0.1:8889/**. If Python is unavailable, use Codex as below to locate an installed runtime; the kit does not install one.
4. Four app screens open initially. For the investor view, click **Emergency team**, choose **Columns 4**, and collapse **Choose accounts**. This shows Patient 1, Hospital 1, Cardiologist 1 and Ambulance 1. Each family has three accounts. Try zoom, Expand/Restore or the optional iPhone frame. Your other laptop does not automatically inherit this PC's browser layout.
5. Stop the kit with **Ctrl+C** in its launcher window. Do not stop unrelated servers or reset Firebase.

## Open it in ChatGPT Codex

Sign into the same ChatGPT account on the other laptop. In desktop ChatGPT, open Codex and choose the extracted kit as a local project folder (use **Edit project → Add folder** if available). Paste:

> Read AGENTS.md and CODEX-HANDOFF.md in this folder. Find an available local Python 3.10+ runtime. Run start.py --check, then launch this private MyDox test room, select Emergency team, choose Columns 4 and collapse Choose accounts to show its four phones. Keep the existing Firebase backend and test records unchanged; do not seed, reset, install or deploy anything.

A synced conversation does **not** upload this folder or make it accessible on another computer. You must transfer and select the extracted local folder. See [OpenAI's project documentation](https://learn.chatgpt.com/docs/projects).

## Test code and shared data

**Test booking / duty OTP: 7777.** This is a service confirmation code, not an SMS/Firebase login code. Booked-time, payment, assignment, status and expiry checks still apply. Real SMS, background push, payments and live medical dispatch are not exercised.

The kit uses the existing synthetic database **mydoxxx-dev-261102 / mydoxxx-testing**. It is not an offline copy: actions in either laptop update the same synthetic records. Avoid two people editing the same test booking unexpectedly. The preserved default database and original/recovery backends remain separate. Use fictional information only.

## If it does not start

- Run `python start.py --check` (or `py -3 start.py --check` on Windows). This checks local files/accounts/ports only; it starts nothing and makes no Firebase requests.
- If a port is occupied, do not kill another app. Use `python start.py --port 8989 --role-port 8991`. The console then opens on **http://127.0.0.1:8989/**, with 36 role ports 8991–9026.
- To ask Codex to open the browser itself, launch with `--no-browser`. Keep that process alive while testing.
- A password/sign-in error may mean the owner changed or revoked the private test logins. Ask the owner for a refreshed kit; do not enable Auth providers, reset passwords or seed accounts yourself.
- If integrity validation fails, compare the ZIP's external SHA-256 file, then extract a fresh copy. Do not edit compiled app files or the private credential file to bypass checks.

The ZIP is not encrypted. Anyone holding it can use its test logins while they remain enabled. Do not place it in a public Drive link, Netlify deployment, Git repository or shared investor download. Only the local app interface should be presented to investors.

Once this kit is running on the second laptop, the original PC can be turned off. The second laptop needs its own internet connection; its local browser layout is saved separately while Firebase test data is shared.
