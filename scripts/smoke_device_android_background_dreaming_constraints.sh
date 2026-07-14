#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
PACKAGE_ID="top.simitalk.aichat"
CHARGING_PACKAGE="${CHARGING_PACKAGE:-top.simitalk.aichat.chargingconstraintsmoke}"
NETWORK_PACKAGE="${NETWORK_PACKAGE:-top.simitalk.aichat.networkconstraintsmoke}"
CROSS_DAY_PACKAGE="$PACKAGE_ID.backgroundsmoke"
CROSS_DAY_STATE="${BACKGROUND_STATE_PATH:-$PWD/.omx/state/android-background-dreaming-cross-day.state}"
INITIAL_DELAY_SECONDS="${INITIAL_DELAY_SECONDS:-30}"
BLOCKED_WAIT_SECONDS="${BLOCKED_WAIT_SECONDS:-45}"
RESULT_WAIT_SECONDS="${RESULT_WAIT_SECONDS:-300}"
RUN_ID="$(date +%Y%m%d%H%M%S)"
CHILD_PID=""
ORIGINAL_WIFI_STATE=""
CHARGING_RELEASE_VERIFIED=0

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required" >&2
  exit 1
fi
if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
  echo "Android device $DEVICE_ID is not available" >&2
  exit 1
fi
for smoke_package in "$CHARGING_PACKAGE" "$NETWORK_PACKAGE"; do
  if [[ "$smoke_package" == "$PACKAGE_ID" || \
    "$smoke_package" == "$CROSS_DAY_PACKAGE" || \
    "$smoke_package" != "$PACKAGE_ID".* ]]; then
    echo "Unsafe constraint smoke package: $smoke_package" >&2
    exit 2
  fi
done
if [[ "$CHARGING_PACKAGE" == "$NETWORK_PACKAGE" ]]; then
  echo "Charging and network smoke packages must be different" >&2
  exit 2
fi
if [[ ! -f "$CROSS_DAY_STATE" ]]; then
  echo "Cross-day state is missing; refusing to run alongside an unknown device state" >&2
  exit 2
fi
ORIGINAL_WIFI_STATE="$(
  adb -s "$DEVICE_ID" shell settings get global wifi_on | tr -d '\r'
)"
if [[ "$ORIGINAL_WIFI_STATE" != "1" ]]; then
  echo "Wi-Fi must already be enabled so the smoke can restore the user's original state" >&2
  exit 2
fi

assert_cross_day_intact() {
  local packages jobs
  [[ -f "$CROSS_DAY_STATE" ]]
  packages="$(
    adb -s "$DEVICE_ID" shell pm list packages "$CROSS_DAY_PACKAGE"
  )"
  grep -q "$CROSS_DAY_PACKAGE" <<<"$packages"
  jobs="$(adb -s "$DEVICE_ID" shell dumpsys jobscheduler)"
  grep -Fq \
    "$CROSS_DAY_PACKAGE/androidx.work.impl.background.systemjob.SystemJobService" \
    <<<"$jobs"
}

restore_device_state() {
  adb -s "$DEVICE_ID" shell cmd battery reset >/dev/null 2>&1 || true
  if [[ "$ORIGINAL_WIFI_STATE" == "1" ]]; then
    adb -s "$DEVICE_ID" shell svc wifi enable >/dev/null 2>&1 || true
  else
    adb -s "$DEVICE_ID" shell svc wifi disable >/dev/null 2>&1 || true
  fi
}

stop_active_smoke() {
  if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" >/dev/null 2>&1; then
    kill "$CHILD_PID" >/dev/null 2>&1 || true
    wait "$CHILD_PID" >/dev/null 2>&1 || true
  fi
  CHILD_PID=""
}

has_unmetered_wifi() {
  local connectivity
  connectivity="$(adb -s "$DEVICE_ID" shell dumpsys connectivity | tr -d '\r')"
  grep -q 'Transports: WIFI.*NOT_METERED.*VALIDATED' <<<"$connectivity"
}

cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT INT TERM
  restore_device_state
  stop_active_smoke
  adb -s "$DEVICE_ID" uninstall "$CHARGING_PACKAGE" >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" uninstall "$NETWORK_PACKAGE" >/dev/null 2>&1 || true
  if ! assert_cross_day_intact; then
    echo "Cross-day Dreaming task was disturbed by the constraint smoke" >&2
    cleanup_status=1
  fi
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' \
    pubspec.yaml pubspec.lock; then
    echo "Temporary sqlite hook remained after constraint smoke" >&2
    cleanup_status=1
  fi
  local release_pid
  release_pid="$(
    adb -s "$DEVICE_ID" shell pidof "$PACKAGE_ID" | tr -d '\r' || true
  )"
  if [[ -z "$release_pid" ]]; then
    adb -s "$DEVICE_ID" shell monkey \
      -p "$PACKAGE_ID" \
      -c android.intent.category.LAUNCHER \
      1 >/dev/null 2>&1 || cleanup_status=1
  fi
  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT INT TERM

wait_for_log_marker() {
  local log_path="$1"
  local marker="$2"
  local timeout_seconds="$3"
  local i
  for ((i = 0; i < timeout_seconds; i++)); do
    if [[ -f "$log_path" ]] && grep -q "$marker" "$log_path"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_job() {
  local package="$1"
  local i job_id jobs
  for ((i = 0; i < 60; i++)); do
    jobs="$(adb -s "$DEVICE_ID" shell dumpsys jobscheduler | tr -d '\r')"
    job_id="$(
      sed -n "s|.*JOB #.*/\([0-9][0-9]*\): .*$package/.*SystemJobService.*|\1|p" \
        <<<"$jobs" \
        | sort -u \
        | sed -n '1p'
    )"
    if [[ -n "$job_id" ]]; then
      printf '%s\n' "$job_id"
      return 0
    fi
    sleep 1
  done
  return 1
}

job_block() {
  local package="$1"
  local jobs
  jobs="$(adb -s "$DEVICE_ID" shell dumpsys jobscheduler | tr -d '\r')"
  awk -v package="$package" '
        index($0, package "/androidx.work.impl.background.systemjob.SystemJobService") { show = 1; count = 0 }
        show { print; count += 1 }
        show && count >= 35 { exit }
      ' <<<"$jobs"
}

expect_strict_run_blocked() {
  local package="$1"
  local job_id="$2"
  local output rc
  set +e
  output="$(
    adb -s "$DEVICE_ID" shell cmd jobscheduler run -s "$package" "$job_id" 2>&1
  )"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "Strict JobScheduler run unexpectedly bypassed constraints: $output" >&2
    return 1
  fi
  echo "$output"
}

run_strict_when_satisfied() {
  local package="$1"
  local job_id="$2"
  adb -s "$DEVICE_ID" shell cmd jobscheduler run -s "$package" "$job_id"
}

start_smoke() {
  local package="$1"
  local requires_charging="$2"
  local requires_unmetered="$3"
  local log_path="$4"
  local prefs_path="$5"
  local host_log="$6"

  SMOKE_PACKAGE="$package" \
  SMOKE_REQUIRES_CHARGING="$requires_charging" \
  SMOKE_REQUIRES_UNMETERED_NETWORK="$requires_unmetered" \
  TRIGGER_MODE=natural \
  SMOKE_INITIAL_DELAY_SECONDS="$INITIAL_DELAY_SECONDS" \
  RESULT_WAIT_SECONDS="$RESULT_WAIT_SECONDS" \
  LOG_PATH="$log_path" \
  PREFS_PATH="$prefs_path" \
    scripts/smoke_device_android_background_dreaming.sh "$DEVICE_ID" \
      >"$host_log" 2>&1 &
  CHILD_PID=$!
  wait_for_log_marker \
    "$log_path" \
    'SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY' \
    180
}

finish_smoke() {
  local host_log="$1"
  local package="$2"
  wait "$CHILD_PID"
  CHILD_PID=""
  grep -q 'ISOLATED_ANDROID_BACKGROUND_DREAMING_SMOKE_OK' "$host_log"
  grep -q "package=$package" "$host_log"
}

assert_cross_day_intact

charging_log="/tmp/simichat-android-dreaming-charging-$RUN_ID.log"
charging_prefs="/tmp/simichat-android-dreaming-charging-$RUN_ID.xml"
charging_host="/tmp/simichat-android-dreaming-charging-host-$RUN_ID.log"

adb -s "$DEVICE_ID" shell cmd battery unplug >/dev/null
sleep 2
if [[ "$(
  adb -s "$DEVICE_ID" shell cmd jobscheduler get-battery-charging | tr -d '\r'
)" != "false" ]]; then
  echo "Unable to simulate a non-charging device" >&2
  exit 1
fi
start_smoke "$CHARGING_PACKAGE" 1 0 \
  "$charging_log" "$charging_prefs" "$charging_host"
charging_job="$(wait_for_job "$CHARGING_PACKAGE")"
sleep "$BLOCKED_WAIT_SECONDS"
adb -s "$DEVICE_ID" logcat -d -v threadtime >"$charging_log"
if grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed' \
  "$charging_log"; then
  echo "Charging-constrained Dreaming ran while the device was unplugged" >&2
  exit 1
fi
charging_job_block="$(job_block "$CHARGING_PACKAGE")"
grep -q 'Requires: charging=true' <<<"$charging_job_block"
grep -Eq 'Unsatisfied constraints:.*CHARGING' <<<"$charging_job_block"
expect_strict_run_blocked "$CHARGING_PACKAGE" "$charging_job" >/dev/null
echo "ANDROID_DREAMING_CHARGING_CONSTRAINT_BLOCKED package=$CHARGING_PACKAGE job=$charging_job"
adb -s "$DEVICE_ID" shell cmd battery set -f ac 1 >/dev/null
adb -s "$DEVICE_ID" shell cmd battery set -f status 2 >/dev/null
for _ in $(seq 1 15); do
  [[ "$(
    adb -s "$DEVICE_ID" shell cmd jobscheduler get-battery-charging \
      | tr -d '\r'
  )" == "true" ]] && break
  sleep 1
done
if [[ "$(
  adb -s "$DEVICE_ID" shell cmd jobscheduler get-battery-charging | tr -d '\r'
)" == "true" ]]; then
  run_strict_when_satisfied "$CHARGING_PACKAGE" "$charging_job"
  finish_smoke "$charging_host" "$CHARGING_PACKAGE"
  CHARGING_RELEASE_VERIFIED=1
  echo "ANDROID_DREAMING_CHARGING_CONSTRAINT_OK package=$CHARGING_PACKAGE job=$charging_job"
else
  echo "ANDROID_DREAMING_CHARGING_CONSTRAINT_RELEASE_UNAVAILABLE package=$CHARGING_PACKAGE job=$charging_job systemCharging=false"
  stop_active_smoke
  adb -s "$DEVICE_ID" uninstall "$CHARGING_PACKAGE" >/dev/null 2>&1 || true
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' \
    pubspec.yaml pubspec.lock; then
    echo "Charging smoke did not restore the temporary sqlite hook" >&2
    exit 1
  fi
fi
adb -s "$DEVICE_ID" shell cmd battery reset -f >/dev/null
assert_cross_day_intact

network_log="/tmp/simichat-android-dreaming-network-$RUN_ID.log"
network_prefs="/tmp/simichat-android-dreaming-network-$RUN_ID.xml"
network_host="/tmp/simichat-android-dreaming-network-host-$RUN_ID.log"

adb -s "$DEVICE_ID" shell svc wifi disable >/dev/null
for _ in $(seq 1 30); do
  [[ "$(
    adb -s "$DEVICE_ID" shell settings get global wifi_on | tr -d '\r'
  )" == "0" ]] && break
  sleep 1
done
[[ "$(
  adb -s "$DEVICE_ID" shell settings get global wifi_on | tr -d '\r'
)" == "0" ]]
start_smoke "$NETWORK_PACKAGE" 0 1 \
  "$network_log" "$network_prefs" "$network_host"
network_job="$(wait_for_job "$NETWORK_PACKAGE")"
sleep "$BLOCKED_WAIT_SECONDS"
adb -s "$DEVICE_ID" logcat -d -v threadtime >"$network_log"
if grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed' \
  "$network_log"; then
  echo "Unmetered-network Dreaming ran without Wi-Fi" >&2
  exit 1
fi
network_job_block="$(job_block "$NETWORK_PACKAGE")"
grep -Eq 'Required constraints:.*CONNECTIVITY' <<<"$network_job_block"
grep -Eq 'Unsatisfied constraints:.*CONNECTIVITY' <<<"$network_job_block"
expect_strict_run_blocked "$NETWORK_PACKAGE" "$network_job" >/dev/null
echo "ANDROID_DREAMING_NETWORK_CONSTRAINT_BLOCKED package=$NETWORK_PACKAGE job=$network_job"
adb -s "$DEVICE_ID" shell svc wifi enable >/dev/null
for _ in $(seq 1 60); do
  if has_unmetered_wifi; then
    break
  fi
  sleep 1
done
has_unmetered_wifi
run_strict_when_satisfied "$NETWORK_PACKAGE" "$network_job"
finish_smoke "$network_host" "$NETWORK_PACKAGE"
echo "ANDROID_DREAMING_NETWORK_CONSTRAINT_OK package=$NETWORK_PACKAGE job=$network_job"

assert_cross_day_intact
if [[ "$CHARGING_RELEASE_VERIFIED" == "1" ]]; then
  echo "ANDROID_DREAMING_CONSTRAINT_SUITE_OK chargingLog=$charging_log networkLog=$network_log"
else
  echo "ANDROID_DREAMING_CONSTRAINT_SUITE_PARTIAL chargingBlocked=true chargingReleased=false networkBlocked=true networkReleased=true chargingLog=$charging_log networkLog=$network_log"
  exit 3
fi
