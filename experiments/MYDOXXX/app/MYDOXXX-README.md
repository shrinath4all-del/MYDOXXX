# MYDOXXX experimental development copy

This folder contains the latest IT-team ZIP supplied on 31 October 2026, extracted
into a separate local Git repository. The original ZIP, Antigravity/CliniGo app,
and Srinath recovery backend remain independent.

Firebase project: **mydoxxx-dev-261102** (MYDOXXX).

## Code baseline and isolation
- Source ZIP SHA-256: cf37c4628e2121e216fd9af42ffd885e2fb66021476020fb0c350344ed5b1213.
- Baseline local commit: be8a23cbd9179a8c76b6326cb57147054fce78b1.
- Local branch: codex/mydoxxx-experiments. No remote/push/publication configured.
- Runtime project validation happens before Firebase initialization.
- Live OTP/SMS, push registration/background processing and payment callables are
  guarded off until the experiment's synthetic-account and access review.
- Fifteen original project maintenance scripts are preserved under
  disabled-original-tools with .disabled extensions. Do not run them.
- Original function implementations remain in source for development; deployment
  entries were removed from this app's firebase.json. The cloud recovery function
  deployment is managed separately and must preserve its side-effect guards.

## Build environment
Use Flutter 3.44.1 / Dart 3.12.1 from:
C:/Users/Lenovo/Documents/New project/.tools/flutter
The PATH Flutter at C:/src/flutter is older and is not the tested SDK.
The received lockfile did not reproduce on the available SDK. This isolated copy
pins pdfrx to 2.2.24 and resolves a fresh pubspec.lock; the original ZIP is unchanged.
Windows/Linux/macOS source folders are preserved in desktop-platforms-held so
Windows plugin symlink requirements do not block Web setup on this PC. Desktop
builds are unsupported until those platform folders and native settings are
reviewed. Web build success does not imply Android/iOS/store readiness.

## Test access
A separate compile-time MYDOXXX_TEST_LAB build now provides one-click synthetic
role logins while retaining the latest IT dashboards. It connects only to the
named mydoxxx-testing Firestore database, never copied recovery records.
See [shared test lab guide](MYDOXXX-TEST-LAB.md) for setup, flows and limitations.
The regular build continues to use its guarded phone/OTP login.

## Native install note
Current Android/iOS bundle is com.mydox.app. A future experiment APK using this ID
could replace the original installed app. Register/configure a distinct experiment
package before side-by-side device installation. No APK was installed here.

## Next development steps
1. Confirm the final new Firebase target and immutable recovery backups.
2. Use the isolated shared test lab for synthetic multi-role tests.
3. Review role/ownership rules and test reads/writes across isolated sessions.
4. Test acceptance, chatting, roster, scoring and payment test-mode flows.
5. Enable an external service only after explicit scoped review and testing.

## Validation of this experimental build
- Release Web build passed against mydoxxx-dev-261102.
- 323 Flutter tests passed, one skipped, zero failures.
- Analyzer: zero errors, two pre-existing warnings, 61 information notices.
- Startup guard, platform config and compiled Web output contain the new project;
  no original/CliniGo/recovery-backup project references remain in active output.
- No APK installation, public deployment, external payment or SMS was performed.
- Synthetic multi-role test mode is described in MYDOXXX-TEST-LAB.md.
- Full production backend workflow acceptance remains pending.

See MYDOXXX-VALIDATION.json and MYDOXXX-ISOLATION-CHECK.json for the recorded checks.
