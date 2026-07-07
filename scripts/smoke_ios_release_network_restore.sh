#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-00008110-0016349A3A20A01E}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUNDLE_ID="${BUNDLE_ID:-top.simitalk.aichat}"
APP_PATH="${APP_PATH:-build/ios/iphoneos/Runner.app}"
RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"
RUN_ID="${RUN_ID:-ios-release-network-$(date +%Y%m%d%H%M%S)}"
RESULT_SOURCE="Documents/ai_chat/release_network_smoke"
RESULT_FILE_NAME="ios-release-network-smoke.json"
READY_MARKER="SIMICHAT_RELEASE_NETWORK_READY"
NEEDS_NORMAL_RESTORE=0
LAUNCHED_PID=""

source scripts/lib/release_pubspec_hook.sh

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for iOS release network smoke" >&2
  exit 1
fi

resolve_core_device() {
  local requested="$1"
  local device_info
  device_info="$(mktemp /tmp/simichat-ios-network-device.XXXXXX)"
  if xcrun devicectl device info details \
    --device "$requested" \
    --json-output "$device_info" >/dev/null 2>&1; then
    local resolved
    resolved="$(python3 - "$device_info" "$requested" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print(sys.argv[2])
    sys.exit(0)
result = data.get("result", {})
identifier = result.get("identifier")
udid = result.get("hardwareProperties", {}).get("udid")
name = result.get("deviceProperties", {}).get("name")
print(identifier or udid or name or sys.argv[2])
PY
)"
    if [[ -n "$resolved" && "$resolved" != "$requested" ]]; then
      echo "Resolved iOS device id $requested to CoreDevice id $resolved" >&2
      requested="$resolved"
    fi
  fi
  rm -f "$device_info"
  printf '%s\n' "$requested"
}

terminate_existing_runner() {
  local device="$1"
  local pids
  pids="$({
    xcrun devicectl device info processes --device "$device" 2>/dev/null \
      | awk '/\/Runner\.app\/Runner/ {print $1}'
  } || true)"
  for pid in ${pids:-}; do
    echo "Terminating existing iOS Runner pid $pid" >&2
    xcrun devicectl device process terminate \
      --device "$device" \
      --pid "$pid" \
      --kill \
      --timeout 10 >/dev/null 2>&1 || true
  done
}

install_release_app() {
  local device="$1"
  local install_json
  install_json="$(mktemp /tmp/simichat-ios-network-install.XXXXXX)"
  xcrun devicectl device install app \
    --device "$device" \
    --json-output "$install_json" \
    "$APP_PATH" >/dev/null
  python3 - "$install_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
result = data.get("result", {})
apps = result.get("installedApplications") or []
app = apps[0] if apps else result.get("app", {})
print("Installed release app:")
for key in ("bundleID", "databaseSequenceNumber"):
    value = app.get(key)
    if value is not None:
        print(f"- {key}: {value}")
PY
  rm -f "$install_json"
}

launch_release_app() {
  local device="$1"
  local launch_json
  launch_json="$(mktemp /tmp/simichat-ios-network-launch.XXXXXX)"
  xcrun devicectl device process launch \
    --device "$device" \
    --terminate-existing \
    --timeout 30 \
    --json-output "$launch_json" \
    "$BUNDLE_ID" >/dev/null
  LAUNCHED_PID="$(python3 - "$launch_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
process = data.get("result", {}).get("process", {})
pid = process.get("processIdentifier") or process.get("pid")
print(pid or "")
PY
)"
  echo "Launched release app:"
  echo "- pid: ${LAUNCHED_PID:-unavailable}"
  rm -f "$launch_json"
}

assert_device_unlocked_for_launch() {
  local device="$1"
  local preflight_json
  preflight_json="$(mktemp /tmp/simichat-ios-network-unlock-preflight.XXXXXX)"
  echo "Checking iOS device unlock state before installing network smoke build..."
  if xcrun devicectl device process launch \
    --device "$device" \
    --timeout 10 \
    --json-output "$preflight_json" \
    "$BUNDLE_ID" >/dev/null 2>&1; then
    rm -f "$preflight_json"
    return 0
  fi

  if grep -qi 'Locked' "$preflight_json" 2>/dev/null; then
    echo "Refusing to install iOS network smoke build while device is locked" >&2
    cat "$preflight_json" >&2 || true
    rm -f "$preflight_json"
    exit 2
  fi

  echo "Refusing to install iOS network smoke build because launch preflight did not prove the device is unlocked" >&2
  cat "$preflight_json" >&2 || true
  rm -f "$preflight_json"
  exit 2
}

copy_smoke_result() {
  local device="$1"
  local destination="$2"
  rm -rf "$destination"
  mkdir -p "$destination"
  xcrun devicectl device copy from \
    --device "$device" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$RESULT_SOURCE" \
    --destination "$destination" >/dev/null 2>&1
}

find_result_file() {
  local destination="$1"
  find "$destination" -name "$RESULT_FILE_NAME" -type f | head -1
}

result_status() {
  local file="$1"
  python3 - "$file" "$RUN_ID" "$READY_MARKER" <<'PY'
import json
import sys

path, run_id, ready_marker = sys.argv[1:4]
data = json.load(open(path))
if data.get("runId") != run_id:
    print("mismatch")
    sys.exit(2)
status = data.get("status")
if status == "ready" and data.get("marker") == ready_marker:
    print("ready")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    sys.exit(0)
if status == "passed":
    print("passed")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    sys.exit(0)
if status == "failed":
    print("failed")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    sys.exit(1)
print(status or "unknown")
sys.exit(2)
PY
}

restore_normal_release() {
  local device="$1"
  if [[ "$RESTORE_NORMAL_RELEASE" != "1" ]]; then
    return 0
  fi
  echo "Restoring normal iOS release build without network smoke dart-defines..."
  "$FLUTTER_BIN" --no-version-check build ios --release
  terminate_existing_runner "$device"
  install_release_app "$device"
  launch_release_app "$device" || true
  NEEDS_NORMAL_RESTORE=0
}

DEVICE_ID="$(resolve_core_device "$DEVICE_ID")"
RESULT_DIR="$(mktemp -d /tmp/simichat-ios-network-result.XXXXXX)"
cleanup() {
  local status=$?
  if [[ "$status" != "0" && "${NEEDS_NORMAL_RESTORE:-0}" == "1" ]]; then
    restore_normal_release "${DEVICE_ID:-}" || true
  fi
  rm -rf "$RESULT_DIR"
  simichat_release_pubspec_restore
  exit "$status"
}
trap cleanup EXIT

assert_device_unlocked_for_launch "$DEVICE_ID"
simichat_release_pubspec_setup 0

echo "Building iOS release network smoke runId=$RUN_ID"
"$FLUTTER_BIN" --no-version-check build ios --release \
  --dart-define=SIMICHAT_RELEASE_NETWORK_SMOKE=true \
  --dart-define=SIMICHAT_RELEASE_NETWORK_SMOKE_RUN_ID="$RUN_ID"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing release app: $APP_PATH" >&2
  exit 1
fi

terminate_existing_runner "$DEVICE_ID"
install_release_app "$DEVICE_ID"
NEEDS_NORMAL_RESTORE=1
launch_release_app "$DEVICE_ID"
if [[ -z "${LAUNCHED_PID:-}" ]]; then
  echo "Could not determine launched Runner pid" >&2
  restore_normal_release "$DEVICE_ID"
  exit 1
fi

ready_seen=0
smoke_status=2
result_file=""
for _ in $(seq 1 60); do
  if copy_smoke_result "$DEVICE_ID" "$RESULT_DIR"; then
    result_file="$(find_result_file "$RESULT_DIR")"
    if [[ -n "$result_file" ]]; then
      set +e
      status_output="$(result_status "$result_file")"
      smoke_status=$?
      set -e
      if [[ "$status_output" == ready* ]]; then
        ready_seen=1
      fi
      if [[ "$status_output" == passed* ]]; then
        echo "iOS release network smoke passed:"
        echo "$status_output"
        smoke_status=0
        break
      fi
      if [[ "$smoke_status" == "1" ]]; then
        echo "$status_output" >&2
        break
      fi
    fi
  fi
  sleep 1
done

if [[ "$ready_seen" != "1" && "$smoke_status" != "0" ]]; then
  echo "Timed out waiting for iOS release network ready marker $READY_MARKER" >&2
fi
if [[ "$smoke_status" == "2" ]]; then
  echo "Timed out waiting for iOS release network smoke pass" >&2
  if [[ -n "$result_file" ]]; then
    cat "$result_file" >&2 || true
  fi
fi

restore_normal_release "$DEVICE_ID"
exit "$smoke_status"
