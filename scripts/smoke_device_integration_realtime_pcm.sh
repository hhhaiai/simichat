#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
ADB_BIN="${ADB_BIN:-adb}"
SMOKE_FLAVOR="realtimepcm"
SMOKE_PACKAGE_ID="top.simitalk.aichat.realtimepcm"
TARGET_PLATFORM="${TARGET_PLATFORM:-android-arm64}"
TEST_TARGET="integration_test/mobile_realtime_pcm_smoke_test.dart"
EXPECTED_DEBUG_APK_NAME="app-${SMOKE_FLAVOR}-debug.apk"
DEBUG_APK_PATH="${DEBUG_APK_PATH:-build/app/outputs/flutter-apk/${EXPECTED_DEBUG_APK_NAME}}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-realtime-pcm-$(date +%Y%m%d%H%M%S).log}"
LOGCAT_PATH="${LOGCAT_PATH:-/tmp/simichat-realtime-pcm-logcat-$(date +%Y%m%d%H%M%S).log}"

if [[ "$(basename "$DEBUG_APK_PATH")" != "$EXPECTED_DEBUG_APK_NAME" ]]; then
  echo "DEBUG_APK_PATH must point to $EXPECTED_DEBUG_APK_NAME: $DEBUG_APK_PATH" >&2
  exit 2
fi
if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
  exit 1
fi
if [[ ! -f android/app/src/main/AndroidManifest.xml ]] || \
  ! grep -q 'android.permission.RECORD_AUDIO' \
    android/app/src/main/AndroidManifest.xml; then
  echo "Android manifest does not declare RECORD_AUDIO" >&2
  exit 1
fi
if [[ "$DEVICE_ID" == *-* ]]; then
  echo "SMOKE_SKIPPED reason=android_device_required device=$DEVICE_ID"
  exit 0
fi
if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "SMOKE_SKIPPED reason=adb_missing device=$DEVICE_ID"
  exit 0
fi

device_state() {
  "$ADB_BIN" -s "$DEVICE_ID" get-state 2>/dev/null \
    | tr -d '\r' | awk 'NF { print $1; exit }'
}

state="$(device_state || true)"
if [[ "$state" != "device" ]]; then
  echo "SMOKE_SKIPPED reason=device_unavailable device=$DEVICE_ID state=${state:-unknown}"
  "$ADB_BIN" devices -l >&2 || true
  exit 0
fi
if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "Flutter executable not found: $FLUTTER_BIN" >&2
  exit 1
fi

package_field() {
  local package="$1"
  local field="$2"
  "$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$package" 2>/dev/null \
    | sed -n "s/.*${field}=//p" | head -1 | tr -d '\r'
}

package_apk_path() {
  local package="$1"
  "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$package" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^package://p' | head -1
}

mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$LOGCAT_PATH")"
: >"$LOG_PATH"

run_logged() {
  local status
  set +e
  "$@" 2>&1 | tee -a "$LOG_PATH"
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

record_audio_state() {
  local line
  line="$(
    "$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE_ID" 2>/dev/null \
      | grep -E 'android\.permission\.RECORD_AUDIO: granted=' \
      | head -1 | tr -d '\r' || true
  )"
  if [[ "$line" == *'granted=true'* ]]; then
    printf 'granted\n'
  elif [[ "$line" == *'granted=false'* ]]; then
    printf 'denied\n'
  else
    printf 'unknown\n'
  fi
}

record_audio_appop() {
  "$ADB_BIN" -s "$DEVICE_ID" shell cmd appops get "$SMOKE_PACKAGE_ID" RECORD_AUDIO \
    2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' || true
}

ensure_record_audio_permission() {
  local stage="$1"
  local before after appop
  before="$(record_audio_state)"
  echo "SMOKE_PERMISSION stage=$stage package=$SMOKE_PACKAGE_ID before=$before"
  if [[ "$before" != "granted" ]]; then
    if ! run_logged "$ADB_BIN" -s "$DEVICE_ID" shell pm grant \
      "$SMOKE_PACKAGE_ID" android.permission.RECORD_AUDIO; then
      echo "Unable to grant RECORD_AUDIO to $SMOKE_PACKAGE_ID" >&2
      return 1
    fi
  fi
  after="$(record_audio_state)"
  appop="$(record_audio_appop)"
  echo "SMOKE_PERMISSION stage=$stage package=$SMOKE_PACKAGE_ID after=$after appops=${appop:-unknown}"
  if [[ "$after" != "granted" ]]; then
    echo "RECORD_AUDIO preflight failed for $SMOKE_PACKAGE_ID" >&2
    return 1
  fi
}

SMOKE_INSTALL_ATTEMPTED=0
PUBSPEC_HOOK_ACTIVE=0
source scripts/lib/release_pubspec_hook.sh

cleanup() {
  local smoke_status=$?
  local cleanup_status=0
  trap - EXIT

  if [[ "$PUBSPEC_HOOK_ACTIVE" == "1" ]]; then
    simichat_release_pubspec_restore || cleanup_status=1
    PUBSPEC_HOOK_ACTIVE=0
  fi

  if [[ "$SMOKE_INSTALL_ATTEMPTED" == "1" ]]; then
    if [[ "$(device_state || true)" != "device" ]]; then
      echo "SMOKE_CLEANUP_UNVERIFIED reason=device_unavailable device=$DEVICE_ID" >&2
      cleanup_status=2
    else
      "$ADB_BIN" -s "$DEVICE_ID" shell am force-stop "$SMOKE_PACKAGE_ID" \
        >/dev/null 2>&1 || cleanup_status=1
      if ! "$ADB_BIN" -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE_ID" \
        >/dev/null 2>&1; then
        cleanup_status=1
      fi
      if [[ -n "$(package_apk_path "$SMOKE_PACKAGE_ID")" ]]; then
        echo "Smoke package remains installed after cleanup: $SMOKE_PACKAGE_ID" >&2
        cleanup_status=1
      fi
      echo "SMOKE_DEBUG_RUNNER_CLEANED package=$SMOKE_PACKAGE_ID " \
        "flavor=$SMOKE_FLAVOR cleanup=uninstall"
    fi
  fi

  if [[ "$(device_state || true)" == "device" ]]; then
    "$ADB_BIN" -s "$DEVICE_ID" shell logcat -d -v threadtime \
      >"$LOGCAT_PATH" 2>/dev/null || true
  else
    echo "SMOKE_LOGCAT_UNAVAILABLE reason=device_unavailable device=$DEVICE_ID" >&2
  fi
  echo "SMOKE_EVIDENCE testLog=$LOG_PATH logcat=$LOGCAT_PATH"
  if [[ "$smoke_status" -ne 0 ]]; then
    exit "$smoke_status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

echo "SMOKE_TARGET package=$SMOKE_PACKAGE_ID flavor=$SMOKE_FLAVOR " \
  "device=$DEVICE_ID test=$TEST_TARGET"

PUBSPEC_HOOK_ACTIVE=1
if ! simichat_release_pubspec_setup 0; then
  echo "Unable to prepare temporary pubspec for realtime PCM smoke" >&2
  exit 2
fi

debug_build_args=(
  --no-version-check build apk --debug --flavor "$SMOKE_FLAVOR" --no-pub
)
if [[ -n "$TARGET_PLATFORM" ]]; then
  debug_build_args+=(--target-platform "$TARGET_PLATFORM")
fi
if ! run_logged "$FLUTTER_BIN" "${debug_build_args[@]}"; then
  echo "Realtime PCM debug APK build failed" >&2
  exit 1
fi
if [[ ! -s "$DEBUG_APK_PATH" ]]; then
  echo "Missing realtime PCM debug APK: $DEBUG_APK_PATH" >&2
  exit 1
fi
if ! simichat_release_pubspec_restore; then
  echo "Unable to restore pubspec after realtime PCM build" >&2
  exit 2
fi
PUBSPEC_HOOK_ACTIVE=0

SMOKE_INSTALL_ATTEMPTED=1
if ! run_logged "$ADB_BIN" -s "$DEVICE_ID" install -r -d "$DEBUG_APK_PATH"; then
  echo "Realtime PCM smoke package install failed: $SMOKE_PACKAGE_ID" >&2
  exit 1
fi
if [[ -z "$(package_apk_path "$SMOKE_PACKAGE_ID")" ]]; then
  echo "Realtime PCM APK did not install as $SMOKE_PACKAGE_ID" >&2
  exit 1
fi
echo "SMOKE_DEBUG_RUNNER_INSTALLED package=$SMOKE_PACKAGE_ID " \
  "flavor=$SMOKE_FLAVOR apk=$DEBUG_APK_PATH installMode=覆盖安装(-r -d)"

if ! ensure_record_audio_permission "debug-runner"; then
  exit 2
fi

"$ADB_BIN" -s "$DEVICE_ID" shell logcat -c >/dev/null 2>&1 || true
set +e
"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --flavor "$SMOKE_FLAVOR" --no-pub -r expanded \
  2>&1 | tee -a "$LOG_PATH"
smoke_status=${PIPESTATUS[0]}
set -e
echo "SMOKE_TEST_EXIT status=$smoke_status flavor=$SMOKE_FLAVOR " \
  "package=$SMOKE_PACKAGE_ID"

if [[ "$smoke_status" -eq 0 ]]; then
  for marker in \
    SIMICHAT_REALTIME_PCM_PLAYBACK_EVIDENCE \
    SIMICHAT_REALTIME_PCM_CAPTURE_EVIDENCE \
    SIMICHAT_REALTIME_PCM_SMOKE_PASS; do
    if ! grep -q "$marker" "$LOG_PATH"; then
      echo "Missing realtime PCM evidence marker: $marker" >&2
      smoke_status=1
    fi
  done
fi
exit "$smoke_status"
