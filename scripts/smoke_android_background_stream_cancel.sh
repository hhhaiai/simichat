#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_background_stream_cancel_smoke_test.dart"

if [[ "$DEVICE_ID" == *-* ]]; then
  cat >&2 <<'EOF'
iOS devices must be validated with a release build for this project.
This Android smoke uses the debug integration runner and is only for adb devices.
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
"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --no-pub -r expanded
