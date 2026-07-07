#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_network_stream_cancel_smoke_test.dart"
REAL_NETWORK_TOGGLE="${REAL_NETWORK_TOGGLE:-0}"
NETWORK_TOGGLE_MODE="${NETWORK_TOGGLE_MODE:-wifi_data}"
RESTORE_FALLBACK_SECONDS="${RESTORE_FALLBACK_SECONDS:-180}"
READY_MARKER="SIMICHAT_NETWORK_STREAM_CANCEL_READY"
INTERRUPTED_MARKER="SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED"

if [[ "$DEVICE_ID" == *-* ]]; then
  echo "Android network stream cancel smoke only supports Android adb devices." >&2
  exit 2
fi

if [[ "$REAL_NETWORK_TOGGLE" != "1" ]]; then
  cat >&2 <<'EOM'
Refusing to toggle device network without REAL_NETWORK_TOGGLE=1.
This smoke starts an in-flight streaming request on the selected Android test
device, disables network after the test prints its stream-ready marker, then
restores network after the test proves the stream was cancelled.
Run explicitly, for example:
  REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
  REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P
EOM
  exit 2
fi

if [[ "$NETWORK_TOGGLE_MODE" != "wifi_data" && "$NETWORK_TOGGLE_MODE" != "airplane" ]]; then
  echo "Unsupported NETWORK_TOGGLE_MODE=$NETWORK_TOGGLE_MODE; expected wifi_data or airplane" >&2
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

FALLBACK_PID=""
NETWORK_DISABLED_FILE="$(mktemp /tmp/simichat-network-stream-disabled.XXXXXX)"
NETWORK_RESTORED_FILE="$(mktemp /tmp/simichat-network-stream-restored.XXXXXX)"

cleanup_network() {
  adb -s "$DEVICE_ID" shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell svc wifi enable >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" shell svc data enable >/dev/null 2>&1 || true
}

disable_network() {
  case "$NETWORK_TOGGLE_MODE" in
    wifi_data)
      echo "Disabling Wi-Fi and mobile data on Android test device $DEVICE_ID" >&2
      adb -s "$DEVICE_ID" shell svc wifi disable >/dev/null
      adb -s "$DEVICE_ID" shell svc data disable >/dev/null || true
      ;;
    airplane)
      echo "Enabling airplane mode on Android test device $DEVICE_ID" >&2
      adb -s "$DEVICE_ID" shell cmd connectivity airplane-mode enable >/dev/null
      ;;
  esac
}

cleanup() {
  local status=$?
  if [[ -n "$FALLBACK_PID" ]] && kill -0 "$FALLBACK_PID" >/dev/null 2>&1; then
    kill "$FALLBACK_PID" >/dev/null 2>&1 || true
    wait "$FALLBACK_PID" >/dev/null 2>&1 || true
  fi
  cleanup_network
  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || true
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f "$PUBSPEC_BACKUP"
  rm -f "$PUBSPEC_LOCK_BACKUP"
  rm -f "$NETWORK_DISABLED_FILE"
  rm -f "$NETWORK_RESTORED_FILE"
  exit "$status"
}
trap cleanup EXIT

# Start from a known-online device state before launching the integration test.
cleanup_network
sleep 2

(
  sleep "$RESTORE_FALLBACK_SECONDS"
  if [[ ! -s "$NETWORK_RESTORED_FILE" ]]; then
    echo "Network stream cancel restore marker was not observed before fallback timeout; restoring network." >&2
    cleanup_network
  fi
) &
FALLBACK_PID="$!"

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
    if [[ "$line" == *"$READY_MARKER"* && ! -s "$NETWORK_DISABLED_FILE" ]]; then
      printf '1\n' >"$NETWORK_DISABLED_FILE"
      disable_network
    fi
    if [[ "$line" == *"$INTERRUPTED_MARKER"* && ! -s "$NETWORK_RESTORED_FILE" ]]; then
      echo "Restoring Android network after stream-interrupted marker." >&2
      printf '1\n' >"$NETWORK_RESTORED_FILE"
      cleanup_network
    fi
  done
test_status="${PIPESTATUS[0]}"
set -e
exit "$test_status"
