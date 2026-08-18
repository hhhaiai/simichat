#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
SMOKE_PACKAGE="${SMOKE_PACKAGE:-top.simitalk.aichat.backgroundsmoke}"
SMOKE_REQUIRES_CHARGING="${SMOKE_REQUIRES_CHARGING:-0}"
SMOKE_REQUIRES_UNMETERED_NETWORK="${SMOKE_REQUIRES_UNMETERED_NETWORK:-0}"
SMOKE_REAL_MODEL="${SMOKE_REAL_MODEL:-0}"
SMOKE_MODEL_CONFIG_FILE="${SMOKE_MODEL_CONFIG_FILE:-}"
SMOKE_MODEL_NAME="none"
SMOKE_MODEL_CONFIG_FILE_NAME="android_background_dreaming_model_smoke.json"
SMOKE_FLAVOR="production"
EXPECTED_APK_NAME="app-${SMOKE_FLAVOR}-debug.apk"
APK_PATH="${APK_PATH:-build/app/outputs/flutter-apk/${EXPECTED_APK_NAME}}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-android-background-dreaming-$(date +%Y%m%d%H%M%S).log}"
PREFS_PATH="${PREFS_PATH:-/tmp/simichat-android-background-dreaming-prefs-$(date +%Y%m%d%H%M%S).xml}"
TRIGGER_MODE="${TRIGGER_MODE:-force}"
DEVICE_IDLE_MODE="${DEVICE_IDLE_MODE:-none}"
BACKGROUND_PROCESS_MODE="${BACKGROUND_PROCESS_MODE:-keep}"
PROCESS_KILL_SETTLE_SECONDS="${PROCESS_KILL_SETTLE_SECONDS:-0}"
BACKGROUND_DETACH_AFTER_SCHEDULE="${BACKGROUND_DETACH_AFTER_SCHEDULE:-0}"
BACKGROUND_STATE_PATH="${BACKGROUND_STATE_PATH:-/tmp/simichat-android-background-dreaming.state}"

if [[ "$(basename "$APK_PATH")" != "$EXPECTED_APK_NAME" ]]; then
  echo "APK_PATH must point to $EXPECTED_APK_NAME: $APK_PATH" >&2
  exit 2
fi

remote_model_config_mode() {
  local path="$1"
  stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null
}

if [[ "$TRIGGER_MODE" != "force" && "$TRIGGER_MODE" != "natural" ]]; then
  echo "TRIGGER_MODE must be force or natural" >&2
  exit 2
fi
if [[ "$DEVICE_IDLE_MODE" != "none" && \
  "$DEVICE_IDLE_MODE" != "require" && \
  "$DEVICE_IDLE_MODE" != "force" ]]; then
  echo "DEVICE_IDLE_MODE must be none, require, or force" >&2
  exit 2
fi
if [[ "$DEVICE_IDLE_MODE" != "none" && "$TRIGGER_MODE" != "natural" ]]; then
  echo "DEVICE_IDLE_MODE requires TRIGGER_MODE=natural" >&2
  exit 2
fi
if [[ "$BACKGROUND_PROCESS_MODE" != "keep" && \
  "$BACKGROUND_PROCESS_MODE" != "kill" ]]; then
  echo "BACKGROUND_PROCESS_MODE must be keep or kill" >&2
  exit 2
fi
if [[ -z "${SMOKE_INITIAL_DELAY_SECONDS+x}" ]]; then
  if [[ "$TRIGGER_MODE" == "natural" ]]; then
    SMOKE_INITIAL_DELAY_SECONDS=30
  else
    SMOKE_INITIAL_DELAY_SECONDS=600
  fi
fi
if [[ -z "${RESULT_WAIT_SECONDS+x}" ]]; then
  if [[ "$TRIGGER_MODE" == "natural" ]]; then
    RESULT_WAIT_SECONDS=240
  else
    RESULT_WAIT_SECONDS=90
  fi
fi
if ! [[ "$SMOKE_INITIAL_DELAY_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "SMOKE_INITIAL_DELAY_SECONDS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$RESULT_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "RESULT_WAIT_SECONDS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$PROCESS_KILL_SETTLE_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "PROCESS_KILL_SETTLE_SECONDS must be a non-negative integer" >&2
  exit 2
fi
if [[ "$BACKGROUND_DETACH_AFTER_SCHEDULE" != "0" && \
  "$BACKGROUND_DETACH_AFTER_SCHEDULE" != "1" ]]; then
  echo "BACKGROUND_DETACH_AFTER_SCHEDULE must be 0 or 1" >&2
  exit 2
fi
if [[ "$SMOKE_REQUIRES_CHARGING" != "0" && \
  "$SMOKE_REQUIRES_CHARGING" != "1" ]]; then
  echo "SMOKE_REQUIRES_CHARGING must be 0 or 1" >&2
  exit 2
fi
if [[ "$SMOKE_REQUIRES_UNMETERED_NETWORK" != "0" && \
  "$SMOKE_REQUIRES_UNMETERED_NETWORK" != "1" ]]; then
  echo "SMOKE_REQUIRES_UNMETERED_NETWORK must be 0 or 1" >&2
  exit 2
fi
if [[ "$SMOKE_REAL_MODEL" != "0" && "$SMOKE_REAL_MODEL" != "1" ]]; then
  echo "SMOKE_REAL_MODEL must be 0 or 1" >&2
  exit 2
fi
if [[ "$SMOKE_REAL_MODEL" == "1" ]]; then
  if [[ -z "$SMOKE_MODEL_CONFIG_FILE" || \
    ! -f "$SMOKE_MODEL_CONFIG_FILE" || \
    ! -s "$SMOKE_MODEL_CONFIG_FILE" ]]; then
    echo "SMOKE_MODEL_CONFIG_FILE must point to a non-empty JSON file" >&2
    exit 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for the remote model smoke configuration" >&2
    exit 1
  fi
  SMOKE_MODEL_CONFIG_MODE="$(
    remote_model_config_mode "$SMOKE_MODEL_CONFIG_FILE"
  )"
  if [[ "$SMOKE_MODEL_CONFIG_MODE" != "600" && \
    "$SMOKE_MODEL_CONFIG_MODE" != "400" ]]; then
    echo "SMOKE_MODEL_CONFIG_FILE permissions must be 600 or 400" >&2
    exit 2
  fi
  if ! jq -e '
    .protocol == "openai_chat" and
    (.baseUrl | type == "string" and length > 0) and
    (.apiKey | type == "string" and length > 0) and
    (.model | type == "string" and length > 0)
  ' "$SMOKE_MODEL_CONFIG_FILE" >/dev/null; then
    echo "SMOKE_MODEL_CONFIG_FILE is not a valid remote model config" >&2
    exit 2
  fi
  SMOKE_MODEL_NAME="$(jq -r '.model' "$SMOKE_MODEL_CONFIG_FILE")"
fi
SMOKE_REQUIRES_CHARGING_DART=false
SMOKE_REQUIRES_UNMETERED_NETWORK_DART=false
SMOKE_REAL_MODEL_DART=false
if [[ "$SMOKE_REQUIRES_CHARGING" == "1" ]]; then
  SMOKE_REQUIRES_CHARGING_DART=true
fi
if [[ "$SMOKE_REQUIRES_UNMETERED_NETWORK" == "1" ]]; then
  SMOKE_REQUIRES_UNMETERED_NETWORK_DART=true
fi
if [[ "$SMOKE_REAL_MODEL" == "1" ]]; then
  SMOKE_REAL_MODEL_DART=true
fi
if [[ "$BACKGROUND_DETACH_AFTER_SCHEDULE" == "1" && \
  ( "$TRIGGER_MODE" != "natural" || "$BACKGROUND_PROCESS_MODE" != "kill" ) ]]; then
  echo "Detached scheduling requires TRIGGER_MODE=natural and BACKGROUND_PROCESS_MODE=kill" >&2
  exit 2
fi

if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]; then
  echo "Refusing to use the production package as the isolated smoke package" >&2
  exit 2
fi
if [[ "$SMOKE_PACKAGE" != "$PACKAGE_ID".* ]]; then
  echo "Isolated smoke package must use the production package namespace: $PACKAGE_ID.*" >&2
  exit 2
fi
if ! [[ "$SMOKE_PACKAGE" =~ ^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$ ]]; then
  echo "Isolated smoke package contains unsafe characters" >&2
  exit 2
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required for the Android background Dreaming smoke" >&2
  exit 1
fi
if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
  echo "Android device $DEVICE_ID is not available" >&2
  exit 1
fi

package_field() {
  local package="$1"
  local field="$2"
  adb -s "$DEVICE_ID" shell dumpsys package "$package" 2>/dev/null \
    | sed -n "s/.*${field}=//p" \
    | head -1 \
    | tr -d '\r'
}

if ! adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
  | grep -q "Package \[$PACKAGE_ID\]"; then
  echo "Normal release app is missing; refusing to run isolated smoke" >&2
  exit 2
fi

ORIGINAL_FIRST_INSTALL_TIME="$(package_field "$PACKAGE_ID" firstInstallTime)"
ORIGINAL_DATA_DIR="$(package_field "$PACKAGE_ID" dataDir)"
if [[ -z "$ORIGINAL_FIRST_INSTALL_TIME" || -z "$ORIGINAL_DATA_DIR" ]]; then
  echo "Unable to capture original release package state" >&2
  exit 1
fi

PUBSPEC_BACKUP="$(mktemp /tmp/simichat-pubspec.XXXXXX)"
PUBSPEC_LOCK_BACKUP="$(mktemp /tmp/simichat-pubspec-lock.XXXXXX)"
cp pubspec.yaml "$PUBSPEC_BACKUP"
cp pubspec.lock "$PUBSPEC_LOCK_BACKUP"
DEVICE_IDLE_FORCED=0
IDLE_STATE_AT_SCHEDULE="not_checked"
IDLE_STATE_AT_RESULT="not_checked"
SMOKE_PID_BEFORE="not_checked"
SMOKE_PID_AFTER="not_checked"
KEEP_SMOKE_PACKAGE=0

cleanup() {
  local smoke_status=$?
  local cleanup_status=0
  trap - EXIT

  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || cleanup_status=$?
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f \
    "$PUBSPEC_BACKUP" \
    "$PUBSPEC_LOCK_BACKUP"

  if [[ "$DEVICE_IDLE_FORCED" == "1" ]]; then
    adb -s "$DEVICE_ID" shell cmd deviceidle unforce >/dev/null \
      || cleanup_status=$?
    adb -s "$DEVICE_ID" shell input keyevent WAKEUP >/dev/null 2>&1 || true
    DEVICE_IDLE_FORCED=0
  fi

  if [[ "$KEEP_SMOKE_PACKAGE" != "1" ]]; then
    adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE" >/dev/null 2>&1 || true
  fi
  if ! adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
    | grep -q "Package \[$PACKAGE_ID\]"; then
    echo "Normal release app disappeared during isolated smoke" >&2
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
  [[ "$restored_first_install_time" == "$ORIGINAL_FIRST_INSTALL_TIME" ]] || cleanup_status=1
  [[ "$restored_data_dir" == "$ORIGINAL_DATA_DIR" ]] || cleanup_status=1
  [[ -n "$release_pid" ]] || cleanup_status=1
  if [[ "$KEEP_SMOKE_PACKAGE" == "1" ]]; then
    if ! adb -s "$DEVICE_ID" shell pm list packages "$SMOKE_PACKAGE" \
      | grep -q "$SMOKE_PACKAGE"; then
      cleanup_status=1
    fi
  elif adb -s "$DEVICE_ID" shell pm list packages "$SMOKE_PACKAGE" \
    | grep -q "$SMOKE_PACKAGE"; then
    cleanup_status=1
  fi
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' pubspec.yaml pubspec.lock; then
    cleanup_status=1
  fi

  echo "NORMAL_RELEASE_RESTORED package=$PACKAGE_ID pid=$release_pid firstInstallTime=$restored_first_install_time dataDir=$restored_data_dir"
  echo "Android background Dreaming log: $LOG_PATH"
  echo "Android background Dreaming prefs: $PREFS_PATH"
  if [[ "$KEEP_SMOKE_PACKAGE" == "1" ]]; then
    echo "Android background Dreaming detached state: $BACKGROUND_STATE_PATH"
  fi
  if [[ "$smoke_status" -ne 0 ]]; then
    exit "$smoke_status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE" >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
s = p.read_text()
if '\nhooks:' not in s:
    p.write_text(s.rstrip() + '\n\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n')
PY

"$FLUTTER_BIN" --no-version-check pub get >/dev/null
ORG_GRADLE_PROJECT_simichatApplicationId="$SMOKE_PACKAGE" \
  "$FLUTTER_BIN" --no-version-check build apk \
    --debug \
    --flavor "$SMOKE_FLAVOR" \
    --target-platform android-arm64 \
    --dart-define=SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE=true \
    --dart-define=SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE_DELAY_SECONDS="$SMOKE_INITIAL_DELAY_SECONDS" \
    --dart-define=SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_CHARGING="$SMOKE_REQUIRES_CHARGING_DART" \
    --dart-define=SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_UNMETERED_NETWORK="$SMOKE_REQUIRES_UNMETERED_NETWORK_DART" \
    --dart-define=SIMICHAT_ANDROID_BACKGROUND_DREAMING_REAL_MODEL="$SMOKE_REAL_MODEL_DART" \
    --no-pub

adb -s "$DEVICE_ID" install -r -t "$APK_PATH"
adb -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE" \
  | grep -q "Package \[$SMOKE_PACKAGE\]"
[[ "$(package_field "$PACKAGE_ID" firstInstallTime)" == "$ORIGINAL_FIRST_INSTALL_TIME" ]]

if [[ "$SMOKE_REAL_MODEL" == "1" ]]; then
  adb -s "$DEVICE_ID" shell \
    "run-as $SMOKE_PACKAGE sh -c 'umask 077; mkdir -p files; cat > files/$SMOKE_MODEL_CONFIG_FILE_NAME'" \
    <"$SMOKE_MODEL_CONFIG_FILE"
fi

adb -s "$DEVICE_ID" logcat -c
adb -s "$DEVICE_ID" shell monkey \
  -p "$SMOKE_PACKAGE" \
  -c android.intent.category.LAUNCHER \
  1 >/dev/null

for _ in $(seq 1 60); do
  adb -s "$DEVICE_ID" logcat -d >"$LOG_PATH"
  grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY' "$LOG_PATH" && break
  sleep 1
done
grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY' "$LOG_PATH"
if [[ "$SMOKE_REAL_MODEL" == "1" ]] && \
  adb -s "$DEVICE_ID" shell run-as "$SMOKE_PACKAGE" test -e \
    "files/$SMOKE_MODEL_CONFIG_FILE_NAME"; then
  echo "One-time remote model smoke configuration was not deleted" >&2
  exit 1
fi
READY_EPOCH="$(date +%s)"

adb -s "$DEVICE_ID" shell input keyevent KEYCODE_HOME
sleep 2

job_ids=""
for _ in $(seq 1 30); do
  job_ids="$(
    adb -s "$DEVICE_ID" shell dumpsys jobscheduler \
      | sed -n "s|.*JOB #.*/\([0-9][0-9]*\): .*$SMOKE_PACKAGE/.*SystemJobService.*|\1|p" \
      | sort -u \
      | tr '\n' ' '
  )"
  [[ -n "$job_ids" ]] && break
  sleep 1
done
if [[ -z "$job_ids" ]]; then
  echo "Unable to locate WorkManager JobScheduler id for $SMOKE_PACKAGE" >&2
  exit 1
fi

if [[ "$DEVICE_IDLE_MODE" == "force" ]]; then
  adb -s "$DEVICE_ID" shell cmd deviceidle force-idle
  DEVICE_IDLE_FORCED=1
fi
if [[ "$DEVICE_IDLE_MODE" != "none" ]]; then
  IDLE_STATE_AT_SCHEDULE="$(
    adb -s "$DEVICE_ID" shell cmd deviceidle get deep | tr -d '\r'
  )"
  if [[ "$IDLE_STATE_AT_SCHEDULE" != "IDLE" && \
    "$IDLE_STATE_AT_SCHEDULE" != "IDLE_MAINTENANCE" ]]; then
    echo "Android device is not in deep idle: $IDLE_STATE_AT_SCHEDULE" >&2
    exit 1
  fi
  if adb -s "$DEVICE_ID" shell cmd deviceidle whitelist \
    | grep -Fq "$SMOKE_PACKAGE"; then
    echo "Isolated smoke package is permanently idle-whitelisted" >&2
    exit 1
  fi
  echo "ANDROID_BACKGROUND_DREAMING_IDLE_READY package=$SMOKE_PACKAGE state=$IDLE_STATE_AT_SCHEDULE"
fi

if [[ "$BACKGROUND_PROCESS_MODE" == "kill" ]]; then
  SMOKE_PID_BEFORE="$(
    adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
  )"
  if [[ -z "$SMOKE_PID_BEFORE" ]]; then
    echo "Unable to locate isolated smoke process before kill" >&2
    exit 1
  fi
  adb -s "$DEVICE_ID" shell am kill "$SMOKE_PACKAGE"
  for _ in $(seq 1 30); do
    if [[ -z "$(
      adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
    )" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -n "$(
    adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
  )" ]]; then
    echo "Isolated smoke process survived am kill" >&2
    exit 1
  fi
  if adb -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE" \
    | grep -q 'stopped=true'; then
    echo "am kill unexpectedly force-stopped the isolated package" >&2
    exit 1
  fi
  echo "ANDROID_BACKGROUND_DREAMING_PROCESS_KILLED package=$SMOKE_PACKAGE pid=$SMOKE_PID_BEFORE"
  if [[ "$PROCESS_KILL_SETTLE_SECONDS" -gt 0 ]]; then
    sleep "$PROCESS_KILL_SETTLE_SECONDS"
    if adb -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE" \
      | grep -q 'stopped=true'; then
      echo "Isolated package became force-stopped while waiting for WorkSpec readiness" >&2
      exit 1
    fi
    if ! adb -s "$DEVICE_ID" shell dumpsys jobscheduler \
      | grep -F "$SMOKE_PACKAGE/" \
      | grep -q 'SystemJobService'; then
      echo "WorkManager JobScheduler job disappeared before forced execution" >&2
      exit 1
    fi
  fi
fi

if [[ "$BACKGROUND_DETACH_AFTER_SCHEDULE" == "1" ]]; then
  scheduled_at_epoch="$(( READY_EPOCH + SMOKE_INITIAL_DELAY_SECONDS ))"
  expected_day_key="$(date -r "$scheduled_at_epoch" +%F)"
  umask 077
  {
    printf 'DEVICE_ID=%q\n' "$DEVICE_ID"
    printf 'PACKAGE_ID=%q\n' "$PACKAGE_ID"
    printf 'SMOKE_PACKAGE=%q\n' "$SMOKE_PACKAGE"
    printf 'ORIGINAL_FIRST_INSTALL_TIME=%q\n' "$ORIGINAL_FIRST_INSTALL_TIME"
    printf 'ORIGINAL_DATA_DIR=%q\n' "$ORIGINAL_DATA_DIR"
    printf 'SMOKE_PID_BEFORE=%q\n' "$SMOKE_PID_BEFORE"
    printf 'JOB_IDS=%q\n' "$job_ids"
    printf 'READY_EPOCH=%q\n' "$READY_EPOCH"
    printf 'SCHEDULED_AT_EPOCH=%q\n' "$scheduled_at_epoch"
    printf 'EXPECTED_DAY_KEY=%q\n' "$expected_day_key"
    printf 'SMOKE_INITIAL_DELAY_SECONDS=%q\n' "$SMOKE_INITIAL_DELAY_SECONDS"
    printf 'LOG_PATH=%q\n' "$LOG_PATH"
    printf 'PREFS_PATH=%q\n' "$PREFS_PATH"
  } >"$BACKGROUND_STATE_PATH"
  KEEP_SMOKE_PACKAGE=1
  echo "ANDROID_BACKGROUND_DREAMING_DETACHED package=$SMOKE_PACKAGE jobs=$job_ids pidBefore=$SMOKE_PID_BEFORE expectedDayKey=$expected_day_key delaySeconds=$SMOKE_INITIAL_DELAY_SECONDS state=$BACKGROUND_STATE_PATH"
  exit 0
fi

if [[ "$TRIGGER_MODE" == "force" ]]; then
  for job_id in $job_ids; do
    if ! adb -s "$DEVICE_ID" shell cmd jobscheduler run \
      -f \
      -n androidx.work.systemjobscheduler \
      "$SMOKE_PACKAGE" \
      "$job_id"; then
      adb -s "$DEVICE_ID" shell cmd jobscheduler run \
        -f \
        "$SMOKE_PACKAGE" \
        "$job_id"
    fi
  done
else
  echo "ANDROID_BACKGROUND_DREAMING_NATURAL_WAIT package=$SMOKE_PACKAGE jobs=$job_ids delaySeconds=$SMOKE_INITIAL_DELAY_SECONDS"
fi

for _ in $(seq 1 "$RESULT_WAIT_SECONDS"); do
  adb -s "$DEVICE_ID" logcat -d -v threadtime >"$LOG_PATH"
  if grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed' "$LOG_PATH"; then
    if [[ "$DEVICE_IDLE_MODE" != "none" ]]; then
      IDLE_STATE_AT_RESULT="$(
        adb -s "$DEVICE_ID" shell cmd deviceidle get deep | tr -d '\r'
      )"
      if [[ "$IDLE_STATE_AT_RESULT" != "IDLE" && \
        "$IDLE_STATE_AT_RESULT" != "IDLE_MAINTENANCE" ]]; then
        echo "Dreaming completed after leaving deep idle: $IDLE_STATE_AT_RESULT" >&2
        exit 1
      fi
    fi
    break
  fi
  sleep 1
done
grep -q 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_RESULT status=completed' "$LOG_PATH"
grep -q 'digest=none' "$LOG_PATH" && exit 1
grep -q 'reflection=none' "$LOG_PATH" && exit 1

if [[ "$BACKGROUND_PROCESS_MODE" == "kill" ]]; then
  SMOKE_PID_AFTER="$(
    adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
  )"
  if [[ -z "$SMOKE_PID_AFTER" || "$SMOKE_PID_AFTER" == "$SMOKE_PID_BEFORE" ]]; then
    echo "JobScheduler did not restart the isolated smoke process" >&2
    exit 1
  fi
  echo "ANDROID_BACKGROUND_DREAMING_PROCESS_RESTARTED package=$SMOKE_PACKAGE before=$SMOKE_PID_BEFORE after=$SMOKE_PID_AFTER"
fi

adb -s "$DEVICE_ID" exec-out run-as "$SMOKE_PACKAGE" \
  cat shared_prefs/FlutterSharedPreferences.xml >"$PREFS_PATH"
grep -q 'assistant_reflection_v1' "$PREFS_PATH"
grep -q 'assistant_reflection_history_v1' "$PREFS_PATH"
grep -q 'dreaming_digest_v1' "$PREFS_PATH"
if grep -q 'assistant_reflection_pending_v1' "$PREFS_PATH"; then
  echo "Reflection pending remained after completed background Dreaming" >&2
  exit 1
fi
if [[ "$SMOKE_REAL_MODEL" == "1" ]]; then
  grep -q '&quot;generationMode&quot;:&quot;model&quot;' "$PREFS_PATH"
  if grep -q 'model_fallback' "$PREFS_PATH"; then
    echo "Reflection used model_fallback instead of the configured real model" >&2
    exit 1
  fi
  PROFILE_PROPOSAL_LINE="$(
    grep 'name="flutter.user_profile_change_proposals_v1"' "$PREFS_PATH" || true
  )"
  if [[ -z "$PROFILE_PROPOSAL_LINE" ]]; then
    echo "Real model background smoke did not persist a profile proposal" >&2
    exit 1
  fi
  if ! grep -q '&quot;generationMode&quot;:&quot;model&quot;' <<<"$PROFILE_PROPOSAL_LINE"; then
    echo "Profile proposal did not use the configured real model" >&2
    exit 1
  fi
  if grep -q 'model_fallback' <<<"$PROFILE_PROPOSAL_LINE"; then
    echo "Profile proposal used model_fallback instead of the configured real model" >&2
    exit 1
  fi
  if grep -q 'name="flutter.user_profile_v1"' "$PREFS_PATH"; then
    echo "Real model profile candidate modified the formal user profile" >&2
    exit 1
  fi
fi

grep 'SIMICHAT_ANDROID_BACKGROUND_DREAMING_' "$LOG_PATH"
RESULT_ELAPSED_SECONDS="$(( $(date +%s) - READY_EPOCH ))"
echo "ISOLATED_ANDROID_BACKGROUND_DREAMING_SMOKE_OK package=$SMOKE_PACKAGE jobs=$job_ids triggerMode=$TRIGGER_MODE idleMode=$DEVICE_IDLE_MODE processMode=$BACKGROUND_PROCESS_MODE requiresCharging=$SMOKE_REQUIRES_CHARGING requiresUnmeteredNetwork=$SMOKE_REQUIRES_UNMETERED_NETWORK realModel=$SMOKE_REAL_MODEL model=$SMOKE_MODEL_NAME pidBefore=$SMOKE_PID_BEFORE pidAfter=$SMOKE_PID_AFTER idleStateAtSchedule=$IDLE_STATE_AT_SCHEDULE idleStateAtResult=$IDLE_STATE_AT_RESULT delaySeconds=$SMOKE_INITIAL_DELAY_SECONDS elapsedSeconds=$RESULT_ELAPSED_SECONDS"
