#!/usr/bin/env bash
# Build/check only. Never authenticates to or deploys Firebase/Netlify services.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly APP="$ROOT/experiments/MYDOXXX/app"
readonly ORIGIN='https://mydoxxx-live-test.netlify.app'
readonly FLUTTER_VERSION='3.44.1'
readonly FLUTTER_REVISION='924134a44c189315be2148659913dda1671cbe99'
readonly SDK="$ROOT/.cache/mydoxxx-ci/flutter-$FLUTTER_VERSION"
readonly MODE="${1:---check}"

die() { printf 'MYDOXXX CI stopped: %s\n' "$1" >&2; exit 1; }
validate_netlify_context() {
  [[ "${NETLIFY:-}" == 'true' ]] || die 'Expected the native Netlify build environment.'
  [[ "${CONTEXT:-}" == 'production' ]] || die 'Only production deploy context is approved.'
  [[ "${BRANCH:-}" == 'main' ]] || die 'Only reviewed main is the production branch.'
  [[ "${URL:-}" == "$ORIGIN" ]] || die 'This configuration belongs only to the approved MYDOXXX cloud site.'
  [[ "${REPOSITORY_URL:-}" == 'https://github.com/shrinath4all-del/MYDOXXX' ||
     "${REPOSITORY_URL:-}" == 'https://github.com/shrinath4all-del/MYDOXXX.git' ||
     "${REPOSITORY_URL:-}" == 'git@github.com:shrinath4all-del/MYDOXXX' ||
     "${REPOSITORY_URL:-}" == 'git@github.com:shrinath4all-del/MYDOXXX.git' ]] ||
    die 'Unexpected source repository.'
}

[[ $# -le 1 ]] || die 'Expected one build mode.'
case "$MODE" in
  --netlify|--validate-context) validate_netlify_context ;;
  --check)
    # A misconfigured Netlify command must not bypass production guards.
    if [[ "${NETLIFY:-}" == 'true' ]]; then validate_netlify_context; fi
    ;;
  *) die 'Use --check or --netlify.' ;;
esac
if [[ "$MODE" == '--validate-context' ]]; then
  printf 'Approved context: main -> %s (no build/deployment performed)\n' "$ORIGIN"
  exit 0
fi

[[ "$(uname -s)" == 'Linux' ]] || die 'The pinned CI build requires a Linux runner.'
[[ "$(uname -m)" == 'x86_64' ]] || die 'The reviewed runner architecture is Linux x86_64.'
command -v git >/dev/null || die 'git is required.'
command -v node >/dev/null || die 'Node 22 is required.'
command -v python3 >/dev/null || die 'Python 3.11 or later is required.'
node -e 'if (Number(process.versions.node.split(".")[0]) !== 22) process.exit(1)' || die 'Use Node 22.'
python3 -c 'import sys; assert sys.version_info >= (3, 11)' || die 'Use Python 3.11 or later.'
[[ -f "$APP/pubspec.lock" && -f "$APP/lib/config/test_lab_config.dart" ]] || die 'Expected experiment source is absent.'
python3 "$ROOT/scripts/mydoxxx/cloud-test-room/prepare-ci-output.py"
cd "$ROOT"

# Explicitly empty Netlify Functions directory: recovered Firebase functions
# and the existing broker are never part of this static publishing pipeline.
mkdir -p "$ROOT/.netlify/no-functions"
[[ -z "$(find "$ROOT/.netlify/no-functions" -mindepth 1 -print -quit)" ]] || die 'The static-only functions directory is not empty.'

printf 'Running offline viewer, broker and packaging checks...\n'
node --test \
  scripts/mydoxxx/test-console.test.cjs \
  scripts/mydoxxx/cloud-test-room/*.test.cjs \
  experiments/MYDOXXX/cloud-test-room-broker/test/*.test.cjs
# This invocation prepares/asserts mocked rule cases only. Never add --remote.
node experiments/MYDOXXX/cloud-test-room-rules/verify-rules.cjs
python3 -m unittest discover -s scripts/mydoxxx/cloud-test-room -p 'test_*.py' -v

printf 'Preparing official Flutter %s at the reviewed commit...\n' "$FLUTTER_VERSION"
if [[ ! -e "$SDK" ]]; then
  mkdir -p "$(dirname "$SDK")"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$SDK"
fi
[[ -d "$SDK/.git" ]] || die 'SDK cache is not the expected Git checkout.'
[[ "$(git -C "$SDK" remote get-url origin)" == 'https://github.com/flutter/flutter.git' ]] || die 'SDK origin differs from official Flutter.'
[[ "$(git -C "$SDK" rev-parse HEAD)" == "$FLUTTER_REVISION" ]] || die 'Flutter release commit changed.'
[[ -z "$(git -C "$SDK" status --porcelain --untracked-files=normal)" ]] || die 'SDK source contains unexpected changes.'
export FLUTTER_ROOT="$SDK"
export PATH="$SDK/bin:$PATH"
export CI=true
export PUB_HOSTED_URL='https://pub.dev'
export FLUTTER_STORAGE_BASE_URL='https://storage.googleapis.com'
flutter config --no-analytics --enable-web
flutter precache --web --linux
# Do not assume Netlify's image has every native test dependency, or attempt
# privileged package installation there. Report an actual missing library.
readonly TEST_RUNTIME="$SDK/bin/cache/artifacts/engine/linux-x64/flutter_tester"
[[ -f "$TEST_RUNTIME" ]] || die 'Flutter Linux test runtime was not installed.'
readonly RUNTIME_DEPS="$(ldd "$TEST_RUNTIME")"
if [[ "$RUNTIME_DEPS" == *'not found'* ]]; then
  printf '%s\n' "$RUNTIME_DEPS" >&2
  die 'Runner is missing a Flutter test library; review the build image before retrying.'
fi
flutter --version --machine > "$ROOT/.cache/mydoxxx-ci/flutter-version.json"
python3 - "$ROOT/.cache/mydoxxx-ci/flutter-version.json" <<'PY'
import json, sys
version = json.load(open(sys.argv[1], encoding='utf-8'))
assert version['frameworkVersion'] == '3.44.1'
assert version['frameworkRevision'] == '924134a44c189315be2148659913dda1671cbe99'
assert version['dartSdkVersion'].split()[0] == '3.12.1'
PY

cd "$APP"
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
flutter analyze --no-pub \
  lib/config/test_lab_config.dart lib/main.dart \
  lib/screens/test_lab/test_lab_login_screen.dart \
  lib/screens/test_lab/test_lab_cloud_bridge_stub.dart \
  lib/screens/test_lab/test_lab_cloud_bridge_web.dart \
  test/test_lab_cloud_login_test.dart
readonly TESTS=(test/test_lab_cloud_login_test.dart test/test_lab_isolation_test.dart)
flutter test --no-pub "${TESTS[@]}"
flutter test --no-pub --dart-define=MYDOXXX_TEST_LAB=true "${TESTS[@]}"
flutter test --no-pub \
  --dart-define=MYDOXXX_TEST_LAB=true \
  --dart-define=MYDOXXX_CLOUD_TEST_LAB=true \
  --dart-define=MYDOXXX_TEST_ORIGIN="$ORIGIN" "${TESTS[@]}"
flutter build web --release --no-pub --base-href /panel/ \
  --dart-define=MYDOXXX_TEST_LAB=true \
  --dart-define=MYDOXXX_CLOUD_TEST_LAB=true \
  --dart-define=MYDOXXX_TEST_ORIGIN="$ORIGIN" \
  --output=build/web-cloud-lab
cd "$ROOT"
python3 scripts/mydoxxx/cloud-test-room/package-site.py --ci --output dist/cloud-test-room
[[ -f dist/cloud-test-room/index.html && -f dist/cloud-test-room/panel/main.dart.js ]] || die 'Cloud publish output is incomplete.'
[[ -z "$(find "$ROOT/.netlify/no-functions" -mindepth 1 -print -quit)" ]] || die 'Functions appeared during a static build.'
printf 'Cloud checks and static package complete: dist/cloud-test-room\n'
