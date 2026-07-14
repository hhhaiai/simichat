#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-status}"
if [[ "$#" -gt 0 ]]; then
  shift
fi

STATE_PATH="${BACKGROUND_STATE_PATH:-$PWD/.omx/state/android-background-dreaming-cross-day.state}"

load_state() {
  if [[ ! -f "$STATE_PATH" ]]; then
    echo "Cross-day Dreaming state does not exist: $STATE_PATH" >&2
    exit 2
  fi
  # The state file is generated locally with printf %q and mode 0600.
  # shellcheck disable=SC1090
  source "$STATE_PATH"
}

package_field() {
  local package="$1"
  local field="$2"
  adb -s "$DEVICE_ID" shell dumpsys package "$package" 2>/dev/null \
    | sed -n "s/.*${field}=//p" \
    | head -1 \
    | tr -d '\r'
}

require_device() {
  if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
    echo "Android device $DEVICE_ID is not available" >&2
    exit 1
  fi
}

restore_release_and_remove_smoke() {
  local cleanup_status=0
  adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE" >/dev/null 2>&1 || true
  if ! adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
    | grep -q "Package \[$PACKAGE_ID\]"; then
    echo "Normal release app is missing during cross-day cleanup" >&2
    cleanup_status=1
  else
    adb -s "$DEVICE_ID" shell am force-stop "$PACKAGE_ID" >/dev/null 2>&1 || true
    adb -s "$DEVICE_ID" shell monkey \
      -p "$PACKAGE_ID" \
      -c android.intent.category.LAUNCHER \
      1 >/dev/null 2>&1 || cleanup_status=$?
  fi

  local restored_first_install_time restored_data_dir release_pid
  restored_first_install_time="$(package_field "$PACKAGE_ID" firstInstallTime)"
  restored_data_dir="$(package_field "$PACKAGE_ID" dataDir)"
  release_pid="$(adb -s "$DEVICE_ID" shell pidof "$PACKAGE_ID" | tr -d '\r' || true)"
  [[ "$restored_first_install_time" == "$ORIGINAL_FIRST_INSTALL_TIME" ]] \
    || cleanup_status=1
  [[ "$restored_data_dir" == "$ORIGINAL_DATA_DIR" ]] || cleanup_status=1
  [[ -n "$release_pid" ]] || cleanup_status=1
  if adb -s "$DEVICE_ID" shell pm list packages "$SMOKE_PACKAGE" \
    | grep -q "$SMOKE_PACKAGE"; then
    cleanup_status=1
  fi
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' pubspec.yaml pubspec.lock; then
    cleanup_status=1
  fi
  rm -f "$STATE_PATH"
  echo "CROSS_DAY_NORMAL_RELEASE_RESTORED package=$PACKAGE_ID pid=$release_pid firstInstallTime=$restored_first_install_time dataDir=$restored_data_dir"
  return "$cleanup_status"
}

case "$MODE" in
  schedule)
    mkdir -p "$(dirname "$STATE_PATH")"
    if [[ -f "$STATE_PATH" ]]; then
      echo "Cross-day Dreaming state already exists; verify or cleanup first: $STATE_PATH" >&2
      exit 2
    fi
    run_id="$(date +%Y%m%d%H%M%S)"
    export TRIGGER_MODE=natural
    export BACKGROUND_PROCESS_MODE=kill
    export BACKGROUND_DETACH_AFTER_SCHEDULE=1
    export BACKGROUND_STATE_PATH="$STATE_PATH"
    export SMOKE_INITIAL_DELAY_SECONDS="${SMOKE_INITIAL_DELAY_SECONDS:-86400}"
    export PROCESS_KILL_SETTLE_SECONDS=0
    export RESULT_WAIT_SECONDS=1
    export LOG_PATH="${LOG_PATH:-/tmp/simichat-android-background-dreaming-cross-day-$run_id.log}"
    export PREFS_PATH="${PREFS_PATH:-/tmp/simichat-android-background-dreaming-cross-day-$run_id.xml}"
    exec scripts/smoke_device_android_background_dreaming.sh \
      "${1:-${DEVICE_ID:-37101FDJH0077P}}"
    ;;
  status)
    load_state
    require_device
    echo "CROSS_DAY_STATUS state=$STATE_PATH expectedDayKey=$EXPECTED_DAY_KEY scheduledAtEpoch=$SCHEDULED_AT_EPOCH delaySeconds=$SMOKE_INITIAL_DELAY_SECONDS pidBefore=$SMOKE_PID_BEFORE"
    printf 'smoke_pid='
    adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
    echo
    for job_id in $JOB_IDS; do
      printf 'job_%s_state=' "$job_id"
      adb -s "$DEVICE_ID" shell cmd jobscheduler get-job-state \
        "$SMOKE_PACKAGE" "$job_id" 2>&1 || true
    done
    if adb -s "$DEVICE_ID" exec-out run-as "$SMOKE_PACKAGE" \
      cat shared_prefs/FlutterSharedPreferences.xml >"$PREFS_PATH" 2>/dev/null; then
      grep -E 'dreaming_digest_v1|assistant_reflection_v1|assistant_reflection_history_v1|assistant_reflection_pending_v1' \
        "$PREFS_PATH" || true
    fi
    ;;
  verify)
    load_state
    require_device
    if ! adb -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE" \
      | grep -q "Package \[$SMOKE_PACKAGE\]"; then
      echo "Cross-day smoke package is missing" >&2
      exit 1
    fi
    [[ "$(package_field "$PACKAGE_ID" firstInstallTime)" == "$ORIGINAL_FIRST_INSTALL_TIME" ]]
    [[ "$(package_field "$PACKAGE_ID" dataDir)" == "$ORIGINAL_DATA_DIR" ]]

    if ! adb -s "$DEVICE_ID" exec-out run-as "$SMOKE_PACKAGE" \
      cat shared_prefs/FlutterSharedPreferences.xml >"$PREFS_PATH" 2>/dev/null; then
      echo "Cross-day Dreaming result is not available yet" >&2
      exit 3
    fi
    if ! grep -q 'assistant_reflection_v1' "$PREFS_PATH" \
      || ! grep -q 'assistant_reflection_history_v1' "$PREFS_PATH" \
      || ! grep -q 'dreaming_digest_v1' "$PREFS_PATH"; then
      echo "Cross-day Dreaming / Reflection has not completed yet" >&2
      exit 3
    fi
    if grep -q 'assistant_reflection_pending_v1' "$PREFS_PATH"; then
      echo "Cross-day Reflection is still pending" >&2
      exit 3
    fi
    grep -q "dayKey&amp;quot;:&amp;quot;$EXPECTED_DAY_KEY" "$PREFS_PATH" \
      || grep -q "dayKey&quot;:&quot;$EXPECTED_DAY_KEY" "$PREFS_PATH"
    grep -q "day&amp;quot;:&amp;quot;${EXPECTED_DAY_KEY}T" "$PREFS_PATH" \
      || grep -q "day&quot;:&quot;${EXPECTED_DAY_KEY}T" "$PREFS_PATH"

    adb -s "$DEVICE_ID" logcat -d -v threadtime >"$LOG_PATH"
    smoke_pid_after="$(
      adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
    )"
    if [[ -n "$smoke_pid_after" && "$smoke_pid_after" == "$SMOKE_PID_BEFORE" ]]; then
      echo "Cross-day smoke process was not restarted" >&2
      exit 1
    fi
    echo "CROSS_DAY_ANDROID_BACKGROUND_DREAMING_VERIFIED package=$SMOKE_PACKAGE expectedDayKey=$EXPECTED_DAY_KEY pidBefore=$SMOKE_PID_BEFORE pidAfter=${smoke_pid_after:-not_running}"
    restore_release_and_remove_smoke
    ;;
  cleanup)
    load_state
    require_device
    restore_release_and_remove_smoke
    ;;
  *)
    echo "Usage: $0 schedule [device-id] | status | verify | cleanup" >&2
    exit 2
    ;;
esac
