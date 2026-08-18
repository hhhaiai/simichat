#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
ADB_BIN="${ADB_BIN:-adb}"
SMOKE_FLAVOR="realtimepcm"
SMOKE_PACKAGE_ID="top.simitalk.aichat.realtimepcm"
TEST_TARGET="integration_test/mobile_voice_recording_smoke_test.dart"
EXPECTED_DEBUG_APK_NAME="app-${SMOKE_FLAVOR}-debug.apk"
APK_PATH="${APK_PATH:-build/app/outputs/flutter-apk/${EXPECTED_DEBUG_APK_NAME}}"

if [[ "$(basename "$APK_PATH")" != "$EXPECTED_DEBUG_APK_NAME" ]]; then
  echo "APK_PATH must point to $EXPECTED_DEBUG_APK_NAME: $APK_PATH" >&2
  exit 2
fi
if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
  exit 1
fi
if [[ "$DEVICE_ID" == *-* ]]; then
  echo "SMOKE_SKIPPED reason=android_device_required device=$DEVICE_ID"
  exit 0
fi
if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=adb_missing device=$DEVICE_ID"
  exit 0
fi

device_state() {
  "$ADB_BIN" -s "$DEVICE_ID" get-state 2>/dev/null \
    | tr -d '\r' | awk 'NF { print $1; exit }'
}

state="$(device_state || true)"
if [[ "$state" != "device" ]]; then
  echo "SMOKE_SKIPPED reason=device_unavailable device=$DEVICE_ID state=${state:-unknown}"
  "$ADB_BIN" devices -l >&2 || true
  exit 0
fi
if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "Flutter executable not found: $FLUTTER_BIN" >&2
  exit 1
fi

PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX)"
cp pubspec.yaml "$PUBSPEC_BACKUP"
cp pubspec.lock "$PUBSPEC_LOCK_BACKUP"

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$(device_state || true)" == "device" ]]; then
    "$ADB_BIN" -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE_ID" \
      >/dev/null 2>&1 || true
  fi
  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || true
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f "$PUBSPEC_BACKUP" "$PUBSPEC_LOCK_BACKUP"
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
"$FLUTTER_BIN" --no-version-check build apk \
  --debug \
  --flavor "$SMOKE_FLAVOR" \
  --target-platform android-arm64 \
  --no-pub

if [[ ! -s "$APK_PATH" ]]; then
  echo "Missing realtime voice recording APK: $APK_PATH" >&2
  exit 1
fi

"$ADB_BIN" -s "$DEVICE_ID" install -r -d "$APK_PATH" >/dev/null
if ! "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$SMOKE_PACKAGE_ID" \
  | tr -d '\r' | grep -q '^package:'; then
  echo "Voice recording APK was not installed as $SMOKE_PACKAGE_ID" >&2
  exit 1
fi
"$ADB_BIN" -s "$DEVICE_ID" shell pm grant \
  "$SMOKE_PACKAGE_ID" android.permission.RECORD_AUDIO

echo "SMOKE_DEBUG_RUNNER_INSTALLED package=$SMOKE_PACKAGE_ID " \
  "flavor=$SMOKE_FLAVOR apk=$APK_PATH installMode=覆盖安装(-r -d)"

"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --flavor "$SMOKE_FLAVOR" --no-pub -r expanded
