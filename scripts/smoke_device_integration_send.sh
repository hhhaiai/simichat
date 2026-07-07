#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_real_send_smoke_test.dart"

resolve_flutter_device_id() {
  local requested="$1"
  if [[ "$requested" == *-* ]] && command -v xcrun >/dev/null 2>&1; then
    local device_info
    device_info="$(mktemp /tmp/simichat-device-info.XXXXXX)"
    if xcrun devicectl device info details \
      --device "$requested" \
      --json-output "$device_info" >/dev/null 2>&1; then
      local udid
      udid="$(python3 - "$device_info" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
udid = data.get("result", {}).get("hardwareProperties", {}).get("udid")
if isinstance(udid, str) and udid:
    print(udid)
PY
)"
      if [[ -n "$udid" && "$udid" != "$requested" ]]; then
        echo "Resolved iOS device id $requested to Flutter UDID $udid" >&2
        requested="$udid"
      fi
    fi
    rm -f "$device_info"
  fi
  printf '%s\n' "$requested"
}

DEVICE_ID="$(resolve_flutter_device_id "$DEVICE_ID")"

if [[ "$DEVICE_ID" == *-* ]] && command -v xcrun >/dev/null 2>&1; then
  if xcrun devicectl device info details --device "$DEVICE_ID" >/dev/null 2>&1; then
    cat >&2 <<'EOF'
iOS devices must be validated with a release build for this project.
Use scripts/smoke_ios_release_install_launch.sh instead of the debug integration runner.
EOF
    exit 2
  fi
fi

cleanup_ios_runner_processes() {
  local device="$1"
  if [[ "$device" != *-* ]] || ! command -v xcrun >/dev/null 2>&1; then
    return 0
  fi

  local pids
  pids="$(
    xcrun devicectl device info processes --device "$device" 2>/dev/null \
      | awk '/\/Runner\.app\/Runner/ {print $1}'
  )"
  if [[ -z "$pids" ]]; then
    return 0
  fi

  for pid in $pids; do
    echo "Terminating stale iOS Runner pid $pid" >&2
    xcrun devicectl device process terminate \
      --device "$device" \
      --pid "$pid" \
      --kill \
      --timeout 10 >/dev/null 2>&1 || true
  done
}

cleanup_ios_runner_processes "$DEVICE_ID"

if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
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
