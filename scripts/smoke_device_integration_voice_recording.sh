#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
ADB_BIN="${ADB_BIN:-adb}"
ANDROID_PACKAGE="${ANDROID_PACKAGE:-top.simitalk.aichat}"
TEST_TARGET="integration_test/mobile_voice_recording_smoke_test.dart"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
  exit 1
fi

PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX.yaml)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX.lock)"
cp pubspec.yaml "$PUBSPEC_BACKUP"
cp pubspec.lock "$PUBSPEC_LOCK_BACKUP"
cleanup() {
  local status=$?
  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || true
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f "$PUBSPEC_BACKUP"
  rm -f "$PUBSPEC_LOCK_BACKUP"
  exit "$status"
}
trap cleanup EXIT

python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
if '\nhooks:' not in s:
    p.write_text(s.rstrip() + '\n\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n')
PY

"$FLUTTER_BIN" --no-version-check pub get >/dev/null
"$FLUTTER_BIN" --no-version-check build apk --debug --no-pub >/dev/null
"$ADB_BIN" -s "$DEVICE_ID" install -r "$APK_PATH" >/dev/null
"$ADB_BIN" -s "$DEVICE_ID" shell pm grant "$ANDROID_PACKAGE" android.permission.RECORD_AUDIO || true

"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --no-pub -r expanded
