#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-00008110-0016349A3A20A01E}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUNDLE_ID="${BUNDLE_ID:-top.simitalk.aichat}"
APP_PATH="${APP_PATH:-build/ios/iphoneos/Runner.app}"

source scripts/lib/release_pubspec_hook.sh

install_json=""
launch_json=""
cleanup() {
  rm -f "${install_json:-}" "${launch_json:-}"
  simichat_release_pubspec_restore
}
trap cleanup EXIT

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for iOS release smoke" >&2
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

DEVICE_ID="$(resolve_core_device "$DEVICE_ID")"

simichat_release_pubspec_setup 0
"$FLUTTER_BIN" --no-version-check build ios --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing release app: $APP_PATH" >&2
  exit 1
fi

terminate_existing_runner "$DEVICE_ID"

install_json="$(mktemp /tmp/simichat-ios-install.XXXXXX)"
launch_json="$(mktemp /tmp/simichat-ios-launch.XXXXXX)"

xcrun devicectl device install app \
  --device "$DEVICE_ID" \
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

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
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

if xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null \
  | grep -F "$BUNDLE_ID" >/dev/null; then
  echo "Verified installed app listing contains $BUNDLE_ID"
else
  echo "Installed app listing did not contain $BUNDLE_ID" >&2
  exit 1
fi

if xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null \
  | grep -F '/Runner.app/Runner' >/dev/null; then
  echo "Verified release Runner process is visible"
else
  echo "Release Runner process is not visible after launch" >&2
  exit 1
fi
