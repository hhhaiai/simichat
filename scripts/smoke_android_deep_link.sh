#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_deep_link_smoke_test.dart"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
READY_MARKER="SIMICHAT_DEEP_LINK_READY"
SETTINGS_OK_MARKER="SIMICHAT_DEEP_LINK_SETTINGS_OK"
SETTINGS_TRIGGER_FILE="$(mktemp /tmp/simichat-deep-link-settings.XXXXXX)"
SESSION_TRIGGER_FILE="$(mktemp /tmp/simichat-deep-link-session.XXXXXX)"
PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX)"

if [[ "$DEVICE_ID" == *-* ]]; then
  cat >&2 <<'EOF'
iOS devices must be validated with a release build for this project.
This Android deep link smoke uses the debug integration runner and is only for adb devices.
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
  rm -f "$SETTINGS_TRIGGER_FILE"
  rm -f "$SESSION_TRIGGER_FILE"
  exit "$status"
}
trap cleanup EXIT

open_deep_link() {
  local url="$1"
  echo "Opening Android deep link: $url" >&2
  adb -s "$DEVICE_ID" shell am start -W -f 0x24000000 \
    -a android.intent.action.VIEW \
    -d "$url" \
    -n "$PACKAGE_ID/.MainActivity"
}

open_settings_link_once() {
  if [[ -s "$SETTINGS_TRIGGER_FILE" ]]; then
    return 0
  fi
  printf '1\n' >"$SETTINGS_TRIGGER_FILE"
  open_deep_link 'ai-chat://settings'
}

open_session_link_once() {
  if [[ -s "$SESSION_TRIGGER_FILE" ]]; then
    return 0
  fi
  printf '1\n' >"$SESSION_TRIGGER_FILE"
  open_deep_link 'ai-chat://session/deep-link-target-session'
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
    if [[ "$line" == *"$READY_MARKER"* ]]; then
      if ! open_settings_link_once; then
        exit 1
      fi
    fi
    if [[ "$line" == *"$SETTINGS_OK_MARKER"* ]]; then
      if ! open_session_link_once; then
        exit 1
      fi
    fi
  done
statuses=("${PIPESTATUS[@]}")
test_status="${statuses[0]}"
trigger_status="${statuses[1]}"
set -e
if [[ "$trigger_status" -ne 0 && "$test_status" -eq 0 ]]; then
  exit "$trigger_status"
fi
exit "$test_status"
