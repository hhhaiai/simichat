#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
ADB_BIN="${ADB_BIN:-adb}"
FORMAL_PACKAGE_ID="top.simitalk.aichat"
SMOKE_FLAVOR="modelswitch"
SMOKE_PACKAGE_ID="top.simitalk.aichat.modelswitch"
TEST_TARGET="integration_test/mobile_model_switch_smoke_test.dart"
EXPECTED_DEBUG_APK_NAME="app-${SMOKE_FLAVOR}-debug.apk"
EXPECTED_DEBUG_APK_PATH="$PWD/build/app/outputs/flutter-apk/$EXPECTED_DEBUG_APK_NAME"
REQUESTED_DEBUG_APK_PATH="${DEBUG_APK_PATH:-$EXPECTED_DEBUG_APK_PATH}"
if [[ "$REQUESTED_DEBUG_APK_PATH" != "$EXPECTED_DEBUG_APK_PATH" ]]; then
  echo "DEBUG_APK_PATH must point to the current-worktree smoke APK: $EXPECTED_DEBUG_APK_PATH" >&2
  exit 2
fi
DEBUG_APK_PATH="$EXPECTED_DEBUG_APK_PATH"
TARGET_PLATFORM="${TARGET_PLATFORM:-android-arm64}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d%H%M%S)-$$}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-model-switch-${RUN_ID}.log}"
LOGCAT_PATH="${LOGCAT_PATH:-/tmp/simichat-model-switch-logcat-${RUN_ID}.log}"

if [[ "$SMOKE_PACKAGE_ID" == "$FORMAL_PACKAGE_ID" ||
  "$SMOKE_PACKAGE_ID" != "$FORMAL_PACKAGE_ID".* ]]; then
  echo "Unsafe model-switch smoke package: $SMOKE_PACKAGE_ID" >&2
  exit 2
fi
if [[ ! -f "$TEST_TARGET" ]]; then
  echo "Missing integration test: $TEST_TARGET" >&2
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

resolve_android_tool() {
  local tool="$1"
  local candidate
  local selected=""
  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

  if candidate="$(command -v "$tool" 2>/dev/null)"; then
    printf '%s' "$candidate"
    return 0
  fi

  [[ -n "$sdk_root" ]] || return 1
  if [[ "$tool" == "aapt" ]]; then
    for candidate in "$sdk_root"/build-tools/*/"$tool"; do
      if [[ -x "$candidate" ]]; then
        selected="$candidate"
      fi
    done
  fi

  [[ -n "$selected" ]] || return 1
  printf '%s' "$selected"
}

AAPT_BIN="${AAPT_BIN:-$(resolve_android_tool aapt || true)}"
if [[ -z "$AAPT_BIN" ]]; then
  echo "aapt is required to verify the smoke APK application id" >&2
  exit 2
fi

apk_package_id() {
  local apk_path="$1"
  "$AAPT_BIN" dump badging "$apk_path" 2>/dev/null \
    | sed -n "s/^package: name='\\([^']*\\)'.*/\\1/p" | head -1
}

package_apk_paths() {
  local package="$1"
  "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$package" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^package://p' || true
}

package_apk_path() {
  package_apk_paths "$1" | head -1
}

package_field() {
  local package="$1"
  local field="$2"
  "$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$package" 2>/dev/null \
    | sed -n "s/.*${field}=//p" | head -1 | tr -d '\r'
}

remote_apk_hash() {
  local apk_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    "$ADB_BIN" -s "$DEVICE_ID" exec-out cat "$apk_path" \
      | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    "$ADB_BIN" -s "$DEVICE_ID" exec-out cat "$apk_path" \
      | sha256sum | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available" >&2
    return 1
  fi
}

formal_apk_path="$(package_apk_path "$FORMAL_PACKAGE_ID")"
if [[ -z "$formal_apk_path" ]]; then
  echo "Formal Android package is missing; refusing to modify it: $FORMAL_PACKAGE_ID" >&2
  exit 2
fi

ORIGINAL_FIRST_INSTALL_TIME="$(package_field "$FORMAL_PACKAGE_ID" firstInstallTime)"
ORIGINAL_DATA_DIR="$(package_field "$FORMAL_PACKAGE_ID" dataDir)"
ORIGINAL_FORMAL_APK_PATHS="$(package_apk_paths "$FORMAL_PACKAGE_ID")"
ORIGINAL_FORMAL_APK_HASH="$(remote_apk_hash "$formal_apk_path")"
if [[ -z "$ORIGINAL_FIRST_INSTALL_TIME" || -z "$ORIGINAL_DATA_DIR" ]]; then
  echo "Unable to capture formal package state for $FORMAL_PACKAGE_ID" >&2
  exit 2
fi
if [[ -z "$ORIGINAL_FORMAL_APK_PATHS" || -z "$ORIGINAL_FORMAL_APK_HASH" ]]; then
  echo "Unable to capture formal package APK path/hash for $FORMAL_PACKAGE_ID" >&2
  exit 2
fi
if [[ -n "$(package_apk_path "$SMOKE_PACKAGE_ID")" ]]; then
  echo "Smoke package already exists; refusing to overwrite: $SMOKE_PACKAGE_ID" >&2
  exit 2
fi

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

assert_formal_package_unchanged() {
  local stage="$1"
  local current_apk_path current_apk_paths current_apk_hash
  local first_install_time data_dir
  current_apk_paths="$(package_apk_paths "$FORMAL_PACKAGE_ID")"
  current_apk_path="$(printf '%s\n' "$current_apk_paths" | head -1)"
  if [[ -z "$current_apk_paths" || -z "$current_apk_path" ]]; then
    echo "Formal package APK path is missing at $stage: $FORMAL_PACKAGE_ID" >&2
    return 1
  fi
  first_install_time="$(package_field "$FORMAL_PACKAGE_ID" firstInstallTime)"
  data_dir="$(package_field "$FORMAL_PACKAGE_ID" dataDir)"
  current_apk_hash="$(remote_apk_hash "$current_apk_path")"
  if [[ -z "$current_apk_hash" ]]; then
    echo "Formal package APK hash is missing at $stage: $FORMAL_PACKAGE_ID" >&2
    return 1
  fi
  printf 'SMOKE_FORMAL_PACKAGE_STATE stage=%s package=%s apk=%s apkPaths=%s apkHash=%s firstInstallTime=%s dataDir=%s\n' \
    "$stage" "$FORMAL_PACKAGE_ID" "$current_apk_path" \
    "$(printf '%s' "$current_apk_paths" | tr '\n' ',')" "$current_apk_hash" \
    "$first_install_time" "$data_dir"
  if [[ "$current_apk_paths" != "$ORIGINAL_FORMAL_APK_PATHS" ||
    "$current_apk_hash" != "$ORIGINAL_FORMAL_APK_HASH" ||
    "$current_apk_path" != "$formal_apk_path" ||
    "$first_install_time" != "$ORIGINAL_FIRST_INSTALL_TIME" ||
    "$data_dir" != "$ORIGINAL_DATA_DIR" ]]; then
    echo "Formal package APK/data state changed at $stage" >&2
    return 1
  fi
}

SMOKE_INSTALL_ATTEMPTED=0

cleanup() {
  local smoke_status=$?
  local cleanup_status=0
  local smoke_apk_path
  trap - EXIT

  if [[ "$SMOKE_INSTALL_ATTEMPTED" == "1" ]]; then
    if [[ "$(device_state || true)" != "device" ]]; then
      echo "SMOKE_CLEANUP_UNVERIFIED reason=device_unavailable device=$DEVICE_ID" >&2
      cleanup_status=2
    else
      smoke_apk_path="$(package_apk_path "$SMOKE_PACKAGE_ID")"
      if [[ -z "$smoke_apk_path" ]]; then
        echo "SMOKE_DEBUG_RUNNER_CLEANED package=$SMOKE_PACKAGE_ID " \
          "flavor=$SMOKE_FLAVOR cleanup=already-removed"
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
      if ! assert_formal_package_unchanged "cleanup"; then
        cleanup_status=1
      fi
    fi
  fi

  if [[ "$(device_state || true)" == "device" ]]; then
    "$ADB_BIN" -s "$DEVICE_ID" shell logcat -d -v threadtime \
      >"$LOGCAT_PATH" 2>/dev/null || true
  else
    echo "SMOKE_LOGCAT_UNAVAILABLE reason=device_unavailable device=$DEVICE_ID" >&2
  fi
  echo "SMOKE_FORMAL_PACKAGE_PRESERVED package=$FORMAL_PACKAGE_ID " \
    "apk=$formal_apk_path firstInstallTime=$ORIGINAL_FIRST_INSTALL_TIME " \
    "dataDir=$ORIGINAL_DATA_DIR"
  echo "SMOKE_EVIDENCE testLog=$LOG_PATH logcat=$LOGCAT_PATH"
  if [[ "$smoke_status" -ne 0 ]]; then
    exit "$smoke_status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

echo "SMOKE_TARGET formalPackage=$FORMAL_PACKAGE_ID " \
  "smokePackage=$SMOKE_PACKAGE_ID flavor=$SMOKE_FLAVOR device=$DEVICE_ID " \
  "test=$TEST_TARGET"
printf 'SMOKE_FORMAL_PACKAGE_STATE stage=baseline package=%s apk=%s firstInstallTime=%s dataDir=%s\n' \
  "$FORMAL_PACKAGE_ID" "$formal_apk_path" "$ORIGINAL_FIRST_INSTALL_TIME" \
  "$ORIGINAL_DATA_DIR"

debug_build_args=(
  --no-version-check build apk --debug --flavor "$SMOKE_FLAVOR" --no-pub
)
if [[ -n "$TARGET_PLATFORM" ]]; then
  debug_build_args+=(--target-platform "$TARGET_PLATFORM")
fi
if ! run_logged "$FLUTTER_BIN" "${debug_build_args[@]}"; then
  echo "Debug runner APK build failed for flavor $SMOKE_FLAVOR" >&2
  exit 1
fi
if [[ ! -s "$DEBUG_APK_PATH" ]]; then
  echo "Missing debug runner APK: $DEBUG_APK_PATH" >&2
  exit 1
fi
BUILT_SMOKE_PACKAGE_ID="$(apk_package_id "$DEBUG_APK_PATH")"
if [[ "$BUILT_SMOKE_PACKAGE_ID" != "$SMOKE_PACKAGE_ID" ]]; then
  echo "Smoke APK application id mismatch: expected=$SMOKE_PACKAGE_ID actual=${BUILT_SMOKE_PACKAGE_ID:-missing}" >&2
  exit 2
fi

SMOKE_INSTALL_ATTEMPTED=1
if ! run_logged "$ADB_BIN" -s "$DEVICE_ID" install -r -d "$DEBUG_APK_PATH"; then
  echo "Debug runner coverage install failed for smoke package $SMOKE_PACKAGE_ID" >&2
  exit 1
fi
if [[ -z "$(package_apk_path "$SMOKE_PACKAGE_ID")" ]]; then
  echo "Flavor APK did not install as smoke package: $SMOKE_PACKAGE_ID" >&2
  exit 1
fi
smoke_data_dir="$(package_field "$SMOKE_PACKAGE_ID" dataDir)"
if [[ -z "$smoke_data_dir" || "$smoke_data_dir" == "$ORIGINAL_DATA_DIR" ]]; then
  echo "Smoke package dataDir is not isolated: package=$SMOKE_PACKAGE_ID dataDir=$smoke_data_dir" >&2
  exit 1
fi
echo "SMOKE_DEBUG_RUNNER_INSTALLED package=$SMOKE_PACKAGE_ID " \
  "flavor=$SMOKE_FLAVOR apk=$DEBUG_APK_PATH dataDir=$smoke_data_dir " \
  "installMode=覆盖安装(-r -d)"
if ! assert_formal_package_unchanged "smoke-install"; then
  exit 1
fi

set +e
"$FLUTTER_BIN" --no-version-check test "$TEST_TARGET" \
  -d "$DEVICE_ID" --flavor "$SMOKE_FLAVOR" --no-pub -r expanded \
  2>&1 | tee -a "$LOG_PATH"
smoke_status=${PIPESTATUS[0]}
set -e
echo "SMOKE_TEST_EXIT status=$smoke_status flavor=$SMOKE_FLAVOR " \
  "package=$SMOKE_PACKAGE_ID"

if [[ "$smoke_status" -eq 0 ]]; then
  previous_marker_line=0
  for marker in \
    SIMICHAT_MODEL_SWITCH_BASELINE \
    SIMICHAT_MODEL_SWITCH_UI_ACTION \
    SIMICHAT_MODEL_SWITCH_DB_EVIDENCE \
    SIMICHAT_MODEL_SWITCH_SMOKE_PASS; do
    marker_count="$(grep -F -c "$marker" "$LOG_PATH" || true)"
    marker_line="$(grep -F -n "$marker" "$LOG_PATH" | cut -d: -f1 | head -1)"
    if [[ "$marker_count" != "1" || -z "$marker_line" ||
      "$marker_line" -le "$previous_marker_line" ]]; then
      echo "Invalid model switch evidence marker: marker=$marker count=$marker_count line=${marker_line:-missing}" >&2
      smoke_status=1
    fi
    if [[ -n "$marker_line" ]]; then
      previous_marker_line="$marker_line"
    fi
  done
fi
exit "$smoke_status"
