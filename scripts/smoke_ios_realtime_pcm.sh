#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-iPhone13}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FORMAL_BUNDLE_ID="${FORMAL_BUNDLE_ID:-top.simitalk.aichat}"
SMOKE_BUNDLE_ID="${SMOKE_BUNDLE_ID:-top.simitalk.aichat.realtimepcm}"
BUILD_MODE="${BUILD_MODE:-all}"
TEST_TARGET="integration_test/ios_realtime_pcm_smoke_test.dart"
DRIVER_TARGET="integration_test/ios_realtime_pcm_smoke_driver.dart"
LOG_PATH="${LOG_PATH:-/tmp/simichat-ios-realtime-pcm-$(date +%Y%m%d%H%M%S).log}"
EXPECTED_MARKERS=(
  SIMICHAT_IOS_REALTIME_PCM_SMOKE_START
  SIMICHAT_IOS_REALTIME_PCM_PLAYBACK_EVIDENCE
  SIMICHAT_IOS_REALTIME_PCM_CAPTURE_EVIDENCE
  SIMICHAT_IOS_REALTIME_PCM_STOP_CLEANUP_EVIDENCE
  SIMICHAT_IOS_REALTIME_PCM_NOTIFICATION_EVIDENCE
  SIMICHAT_IOS_REALTIME_PCM_SMOKE_PASS
)

if [[ "$SMOKE_BUNDLE_ID" == "$FORMAL_BUNDLE_ID" ]]; then
  echo "Refusing to run iOS realtime PCM smoke with the formal bundle id: $FORMAL_BUNDLE_ID" >&2
  exit 2
fi
if [[ ! "$SMOKE_BUNDLE_ID" =~ ^top\.simitalk\.aichat\.realtimepcm([.-][a-z0-9-]+)?$ ]]; then
  echo "SMOKE_BUNDLE_ID must remain in the isolated realtimepcm namespace: $SMOKE_BUNDLE_ID" >&2
  exit 2
fi
case "$BUILD_MODE" in
  debug|release|all) ;;
  *)
    echo "BUILD_MODE must be debug, release, or all: $BUILD_MODE" >&2
    exit 2
    ;;
esac

for path in "$TEST_TARGET" "$DRIVER_TARGET" ios/Runner.xcworkspace; do
  if [[ ! -e "$path" ]]; then
    echo "Missing iOS realtime PCM smoke input: $path" >&2
    exit 1
  fi
done

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=flutter_missing device=$DEVICE_ID"
  exit 0
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=xcrun_missing device=$DEVICE_ID"
  exit 0
fi

resolve_core_device() {
  local requested="$1"
  local device_info="/tmp/simichat-ios-realtime-pcm-device-$RANDOM.json"
  if ! xcrun devicectl device info details \
    --device "$requested" \
    --json-output "$device_info" >/dev/null 2>&1; then
    echo "$requested"
    return 0
  fi
  python3 - "$device_info" "$requested" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print(sys.argv[2])
    raise SystemExit(0)
result = data.get("result", {})
print(
    # Flutter's iOS device discovery uses the hardware UDID, while
    # devicectl accepts both the CoreDevice identifier and the UDID. Prefer
    # the UDID so the same resolved value works for both commands.
    result.get("hardwareProperties", {}).get("udid")
    or result.get("identifier")
    or result.get("deviceProperties", {}).get("name")
    or sys.argv[2]
)
PY
}

device_state="/tmp/simichat-ios-realtime-pcm-state-$RANDOM.json"
if ! xcrun devicectl device info details \
  --device "$DEVICE_ID" \
  --json-output "$device_state" >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=device_unavailable device=$DEVICE_ID"
  exit 0
fi

resolved_device="$(resolve_core_device "$DEVICE_ID")"
connection_state="$(python3 - "$device_state" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown")
    raise SystemExit(0)
result = data.get("result", {})
connection = result.get("connectionProperties", {})
print(connection.get("tunnelState") or connection.get("transportType") or "unknown")
PY
)"
if [[ "$connection_state" == "unavailable" ]]; then
  echo "SMOKE_SKIPPED reason=device_unavailable device=$DEVICE_ID state=$connection_state"
  exit 0
fi

lock_state="/tmp/simichat-ios-realtime-pcm-lock-$RANDOM.json"
if ! xcrun devicectl device info lockState \
  --device "$resolved_device" \
  --json-output "$lock_state" >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=device_lock_state_unavailable device=$resolved_device"
  exit 0
fi
unlocked_since_boot="$(python3 - "$lock_state" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown")
    raise SystemExit(0)
print(str(data.get("result", {}).get("unlockedSinceBoot", "unknown")).lower())
PY
)"
if [[ "$unlocked_since_boot" != "true" ]]; then
  echo "SMOKE_SKIPPED reason=device_locked device=$resolved_device unlockedSinceBoot=$unlocked_since_boot"
  exit 0
fi

mkdir -p "$(dirname "$LOG_PATH")"
: >"$LOG_PATH"

run_logged() {
  local status
  set +e
  "$@" 2>&1 | tee -a "$LOG_PATH"
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

PUBSPEC_TMP_DIR=""
prepare_integration_test_dependency() {
  if grep -q '^  integration_test:$' pubspec.yaml; then
    return 0
  fi
  PUBSPEC_TMP_DIR="$(mktemp -d /tmp/simichat-ios-realtime-pcm-pubspec.XXXXXX)"
  cp pubspec.yaml "$PUBSPEC_TMP_DIR/pubspec.yaml.bak"
  cp pubspec.lock "$PUBSPEC_TMP_DIR/pubspec.lock.bak"
  python3 - <<'PY'
from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
needle = '  flutter_test:\n    sdk: flutter\n'
block = needle + '  integration_test:\n    sdk: flutter\n'
if '  integration_test:\n' not in s:
    if needle not in s:
        raise SystemExit('flutter_test dev_dependency block not found')
    s = s.replace(needle, block, 1)
    p.write_text(s)
PY
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null
}

restore_pubspec() {
  if [[ -z "$PUBSPEC_TMP_DIR" ]]; then
    return 0
  fi
  cp "$PUBSPEC_TMP_DIR/pubspec.yaml.bak" pubspec.yaml
  cp "$PUBSPEC_TMP_DIR/pubspec.lock.bak" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get \
    >/tmp/simichat-ios-realtime-pcm-pubspec-restore.log 2>&1 || true
  cp "$PUBSPEC_TMP_DIR/pubspec.lock.bak" pubspec.lock
  rm -rf "$PUBSPEC_TMP_DIR"
  PUBSPEC_TMP_DIR=""
}

cleanup_smoke_app() {
  # The only package this script is allowed to remove is the isolated smoke
  # package. It never uninstalls, clears, or forcibly terminates the formal app.
  xcrun devicectl device uninstall app \
    --device "$resolved_device" \
    "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
}

SMOKE_STARTED=0
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$SMOKE_STARTED" == "1" ]]; then
    cleanup_smoke_app
    echo "SMOKE_ISOLATED_PACKAGE_CLEANED bundle=$SMOKE_BUNDLE_ID"
  fi
  restore_pubspec
  echo "SMOKE_EVIDENCE log=$LOG_PATH device=$resolved_device bundle=$SMOKE_BUNDLE_ID"
  exit "$status"
}
trap cleanup EXIT

echo "SMOKE_TARGET platform=ios device=$resolved_device bundle=$SMOKE_BUNDLE_ID " \
  "formalBundle=$FORMAL_BUNDLE_ID buildMode=$BUILD_MODE test=$TEST_TARGET"
echo "SMOKE_SAFETY formalPackageMutations=none isolatedCleanup=uninstall-only"
echo "SMOKE_PERMISSION action=first-run-iOS-prompt-or-existing-grant " \
  "usageDescription=NSMicrophoneUsageDescription"

# Remove only a stale copy of the isolated package. This also makes an old
# failed run unable to affect the current permission/launch result.
cleanup_smoke_app
prepare_integration_test_dependency

run_mode() {
  local mode="$1"
  local mode_args=(
    --no-version-check
    drive
    --target="$TEST_TARGET"
    --driver="$DRIVER_TARGET"
    -d
    "$resolved_device"
    --no-pub
    --no-keep-app-running
    --timeout=180
  )
  if [[ "$mode" == "release" ]]; then
    mode_args+=(--release)
  else
    mode_args+=(--debug)
  fi

  echo "SMOKE_RUN mode=$mode bundle=$SMOKE_BUNDLE_ID"
  SMOKE_STARTED=1
  # Do not invoke `env` here. This workstation has an RTK `env` shim that
  # intentionally does not exec its arguments, which would make the smoke
  # appear to pass the build command while producing an empty evidence log.
  # A shell assignment on the function call propagates the isolated bundle
  # identifier to the actual Flutter child without touching the formal app.
  if ! FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER="$SMOKE_BUNDLE_ID" \
    run_logged "$FLUTTER_BIN" "${mode_args[@]}"; then
    echo "iOS realtime PCM $mode smoke failed; see $LOG_PATH" >&2
    return 1
  fi

  for marker in "${EXPECTED_MARKERS[@]}"; do
    if ! grep -q "$marker" "$LOG_PATH"; then
      echo "Missing iOS realtime PCM $mode smoke marker: $marker" >&2
      return 1
    fi
  done
  if [[ "$mode" == "debug" ]]; then
    for marker in \
      SIMICHAT_IOS_REALTIME_PCM_INTERRUPTION_EVIDENCE \
      SIMICHAT_IOS_REALTIME_PCM_ROUTE_CHANGE_EVIDENCE; do
      if ! grep -q "$marker" "$LOG_PATH"; then
        echo "Missing iOS realtime PCM Debug notification marker: $marker" >&2
        return 1
      fi
    done
  fi
  echo "SMOKE_MODE_PASS mode=$mode bundle=$SMOKE_BUNDLE_ID"
}

case "$BUILD_MODE" in
  debug)
    run_mode debug
    ;;
  release)
    run_mode release
    ;;
  all)
    run_mode debug
    run_mode release
    ;;
esac

echo "SMOKE_PASS platform=ios realtimePcm=true input=16000/mono/PCM16 " \
  "output=24000/mono/PCM16 interruption=debug-hook routeChange=debug-hook " \
  "audioFiles=none bundle=$SMOKE_BUNDLE_ID"
