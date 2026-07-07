#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-00008110-0016349A3A20A01E}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUNDLE_ID="${BUNDLE_ID:-top.simitalk.aichat}"
APP_PATH="${APP_PATH:-build/ios/iphoneos/Runner.app}"
RESTORE_NORMAL_RELEASE="${RESTORE_NORMAL_RELEASE:-1}"
RUN_ID="${RUN_ID:-ios-release-send-$(date +%Y%m%d%H%M%S)}"
RESULT_SOURCE="Documents/ai_chat/release_smoke"
NEEDS_NORMAL_RESTORE=0

source scripts/lib/release_pubspec_hook.sh

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for iOS release send smoke" >&2
  exit 1
fi

resolve_core_device() {
  local requested="$1"
  local device_info
  device_info="$(mktemp /tmp/simichat-ios-device.XXXXXX)"
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
if identifier:
    print(identifier)
elif udid:
    print(udid)
elif name:
    print(name)
else:
    print(sys.argv[2])
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
  pids="$(
    xcrun devicectl device info processes --device "$device" 2>/dev/null \
      | awk '/\/Runner\.app\/Runner/ {print $1}'
  )"
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
  install_json="$(mktemp /tmp/simichat-ios-release-send-install.XXXXXX)"
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
for key in ("bundleID", "installationURL", "databaseSequenceNumber"):
    value = app.get(key)
    if value is not None:
        print(f"- {key}: {value}")
PY
  rm -f "$install_json"
}

launch_release_app() {
  local device="$1"
  local launch_json
  launch_json="$(mktemp /tmp/simichat-ios-release-send-launch.XXXXXX)"
  xcrun devicectl device process launch \
    --device "$device" \
    --terminate-existing \
    --timeout 30 \
    --json-output "$launch_json" \
    "$BUNDLE_ID" >/dev/null
  python3 - "$launch_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
process = data.get("result", {}).get("process", {})
pid = process.get("processIdentifier") or process.get("pid")
print("Launched release app:")
if pid is not None:
    print(f"- pid: {pid}")
else:
    print("- pid: unavailable in devicectl JSON")
PY
  rm -f "$launch_json"
}

assert_device_unlocked_for_launch() {
  local device="$1"
  local preflight_json
  preflight_json="$(mktemp /tmp/simichat-ios-release-send-unlock-preflight.XXXXXX)"
  echo "Checking iOS device unlock state before installing smoke build..."
  if xcrun devicectl device process launch \
    --device "$device" \
    --timeout 10 \
    --json-output "$preflight_json" \
    "$BUNDLE_ID" >/dev/null 2>&1; then
    rm -f "$preflight_json"
    return 0
  fi

  if grep -qi 'Locked' "$preflight_json" 2>/dev/null; then
    echo "Refusing to install iOS release send smoke build while device is locked" >&2
    cat "$preflight_json" >&2 || true
    rm -f "$preflight_json"
    exit 2
  fi

  echo "Refusing to install iOS release send smoke build because launch preflight did not prove the device is unlocked" >&2
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
  find "$destination" -name 'ios-release-send-smoke.json' -type f | head -1
}

check_result_file() {
  local file="$1"
  python3 - "$file" "$RUN_ID" <<'PY'
import json
import sys

path, run_id = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if data.get("runId") != run_id:
    print(f"waiting for runId {run_id}, got {data.get('runId')}")
    sys.exit(2)
status = data.get("status")
if status == "passed":
    print("iOS release send smoke passed:")
    print(f"- runId: {data.get('runId')}")
    print(f"- reply: {data.get('reply')}")
    request = data.get("request") or {}
    print(f"- request.path: {request.get('path')}")
    print(f"- request.model: {request.get('model')}")
    print(f"- request.lastUser: {request.get('lastUser')}")
    checks = data.get("checks") or {}
    retry = checks.get("retry") or {}
    model_switch = checks.get("modelSwitch") or {}
    stop = checks.get("stop") or {}
    if retry:
        print(f"- retry.requestCountForInitialPrompt: {retry.get('requestCountForInitialPrompt')}")
    if model_switch:
        print(f"- modelSwitch.requestModel: {model_switch.get('requestModel')}")
        print(f"- modelSwitch.timelineRecordCount: {model_switch.get('timelineRecordCount')}")
    if stop:
        print(f"- stop.partialReply: {stop.get('partialReply')}")
        print(f"- stop.requestCompleted: {stop.get('requestCompleted')}")
    sys.exit(0)
if status == "failed":
    print("iOS release send smoke failed:")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    sys.exit(1)
print(f"iOS release send smoke status: {status}")
sys.exit(2)
PY
}

restore_normal_release() {
  local device="$1"
  if [[ "$RESTORE_NORMAL_RELEASE" != "1" ]]; then
    return 0
  fi
  echo "Restoring normal iOS release build without smoke dart-defines..."
  "$FLUTTER_BIN" --no-version-check build ios --release
  terminate_existing_runner "$device"
  install_release_app "$device"
  NEEDS_NORMAL_RESTORE=0
  launch_release_app "$device" || true
}

DEVICE_ID="$(resolve_core_device "$DEVICE_ID")"
RESULT_DIR="$(mktemp -d /tmp/simichat-ios-release-send-result.XXXXXX)"
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

echo "Building iOS release send smoke runId=$RUN_ID"
"$FLUTTER_BIN" --no-version-check build ios --release \
  --dart-define=SIMICHAT_RELEASE_SEND_SMOKE=true \
  --dart-define=SIMICHAT_RELEASE_SMOKE_RUN_ID="$RUN_ID"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing release app: $APP_PATH" >&2
  exit 1
fi

terminate_existing_runner "$DEVICE_ID"
install_release_app "$DEVICE_ID"
NEEDS_NORMAL_RESTORE=1
launch_release_app "$DEVICE_ID"

smoke_status=2
result_file=""
for _ in $(seq 1 45); do
  if copy_smoke_result "$DEVICE_ID" "$RESULT_DIR"; then
    result_file="$(find_result_file "$RESULT_DIR")"
    if [[ -n "$result_file" ]]; then
      set +e
      check_result_file "$result_file"
      smoke_status=$?
      set -e
      if [[ "$smoke_status" == "0" || "$smoke_status" == "1" ]]; then
        break
      fi
    fi
  fi
  sleep 1
done

if [[ "$smoke_status" == "2" ]]; then
  echo "Timed out waiting for iOS release send smoke result" >&2
  if [[ -n "$result_file" ]]; then
    cat "$result_file" >&2 || true
  fi
fi

restore_normal_release "$DEVICE_ID"
exit "$smoke_status"
