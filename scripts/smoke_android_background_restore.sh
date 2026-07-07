#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_background_restore_smoke_test.dart"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
REAL_BACKGROUND_TOGGLE="${REAL_BACKGROUND_TOGGLE:-0}"
BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-3}"
RESTORE_READY_MARKER="SIMICHAT_BACKGROUND_RESTORE_READY"

if [[ "$DEVICE_ID" == *-* ]]; then
  echo "Android background restore smoke only supports Android adb devices." >&2
  exit 2
fi

if [[ "$REAL_BACKGROUND_TOGGLE" != "1" ]]; then
  cat >&2 <<'EOF'
Refusing to background the device without REAL_BACKGROUND_TOGGLE=1.
This smoke sends KEYCODE_HOME to the selected Android test device,
waits briefly, then launches SimiAIChat again to verify foreground restore.
Run explicitly, for example:
  REAL_BACKGROUND_TOGGLE=1 scripts/smoke_android_background_restore.sh 37101FDJH0077P
EOF
  exit 2
fi

if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found in PATH" >&2
  exit 1
fi

if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
  echo "Android device $DEVICE_ID is not available via adb" >&2
  exit 1
fi

PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX)"
RESTORE_TRIGGER_FILE="$(mktemp /tmp/simichat-background-restore-triggered.XXXXXX)"
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
  rm -f "$RESTORE_TRIGGER_FILE"
  exit "$status"
}
trap cleanup EXIT

run_background_restore() {
  if [[ -s "$RESTORE_TRIGGER_FILE" ]]; then
    return 0
  fi
  printf '1\n' >"$RESTORE_TRIGGER_FILE"
  echo "Sending KEYCODE_HOME to Android test device $DEVICE_ID" >&2
  adb -s "$DEVICE_ID" shell input keyevent KEYCODE_HOME >/dev/null
  sleep "$BACKGROUND_SECONDS"
  echo "Launching $PACKAGE_ID after background interval" >&2
  adb -s "$DEVICE_ID" shell monkey -p "$PACKAGE_ID" \
    -c android.intent.category.LAUNCHER 1 >/dev/null
}

python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
if '\nhooks:' not in s:
    p.write_text(s.rstrip() + '\n\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n')
PY

"$FLUTTER_BIN" --no-version-check pub get >/dev/null
set +e
"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --no-pub -r expanded 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == *"$RESTORE_READY_MARKER"* ]]; then
      run_background_restore
    fi
  done
test_status="${PIPESTATUS[0]}"
set -e
exit "$test_status"
