#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGET="integration_test/mobile_network_restore_smoke_test.dart"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
REAL_NETWORK_TOGGLE="${REAL_NETWORK_TOGGLE:-0}"
NETWORK_TOGGLE_MODE="${NETWORK_TOGGLE_MODE:-wifi_data}"
RESTORE_FALLBACK_SECONDS="${RESTORE_FALLBACK_SECONDS:-180}"
RESTORE_READY_MARKER="SIMICHAT_NETWORK_RESTORE_READY"

if [[ "$DEVICE_ID" == *-* ]]; then
  echo "Android network restore smoke only supports Android adb devices." >&2
  exit 2
fi

if [[ "$REAL_NETWORK_TOGGLE" != "1" ]]; then
  cat >&2 <<'EOF'
Refusing to toggle device network without REAL_NETWORK_TOGGLE=1.
This smoke disables network on the selected Android test device,
then restores both after the integration test prints its offline-ready marker.
Run explicitly, for example:
  REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_restore.sh 37101FDJH0077P
  REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_restore.sh 37101FDJH0077P
EOF
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
RESTORE_TRIGGER_FILE="$(mktemp /tmp/simichat-network-restore-triggered.XXXXXX)"

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
  rm -f "$RESTORE_TRIGGER_FILE"
  exit "$status"
}
trap cleanup EXIT

disable_network
sleep 2

(
  sleep "$RESTORE_FALLBACK_SECONDS"
  if [[ ! -s "$RESTORE_TRIGGER_FILE" ]]; then
    echo "Network restore marker was not observed before fallback timeout; restoring network." >&2
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
    if [[ "$line" == *"$RESTORE_READY_MARKER"* && ! -s "$RESTORE_TRIGGER_FILE" ]]; then
      echo "Restoring Android network after offline-ready marker." >&2
      printf '1\n' >"$RESTORE_TRIGGER_FILE"
      cleanup_network
    fi
  done
test_status="${PIPESTATUS[0]}"
set -e
exit "$test_status"
