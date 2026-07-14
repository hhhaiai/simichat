#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PACKAGE_ID="${PACKAGE_ID:-top.simitalk.aichat}"
SMOKE_PACKAGE="${SMOKE_PACKAGE:-top.simitalk.aichat.dreamingsmoke}"
APK_PATH="${APK_PATH:-build/app/outputs/flutter-apk/app-debug.apk}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-dreaming-reflection-device-$(date +%Y%m%d%H%M%S).log}"
PREFS_PATH="${PREFS_PATH:-/tmp/simichat-dreaming-reflection-prefs-$(date +%Y%m%d%H%M%S).xml}"
SMOKE_SQLITE_RECOVERY="${SMOKE_SQLITE_RECOVERY:-0}"

if [[ "$SMOKE_PACKAGE" == "$PACKAGE_ID" ]]; then
  echo "Refusing to use the production package as the isolated smoke package" >&2
  exit 2
fi
if [[ "$SMOKE_PACKAGE" != "$PACKAGE_ID".* ]]; then
  echo "Isolated smoke package must use the production package namespace: $PACKAGE_ID.*" >&2
  exit 2
fi
if [[ "$SMOKE_SQLITE_RECOVERY" != "0" && "$SMOKE_SQLITE_RECOVERY" != "1" ]]; then
  echo "SMOKE_SQLITE_RECOVERY must be 0 or 1" >&2
  exit 2
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required for the Android Dreaming Reflection smoke" >&2
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
  echo "Normal release app is missing; installing it before isolated smoke" >&2
  scripts/smoke_android_release_install_launch.sh "$DEVICE_ID"
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

cleanup() {
  local smoke_status=$?
  local cleanup_status=0
  trap - EXIT

  cp "$PUBSPEC_BACKUP" pubspec.yaml
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  "$FLUTTER_BIN" --no-version-check pub get >/dev/null || cleanup_status=$?
  cp "$PUBSPEC_LOCK_BACKUP" pubspec.lock
  rm -f "$PUBSPEC_BACKUP" "$PUBSPEC_LOCK_BACKUP"

  adb -s "$DEVICE_ID" uninstall "$SMOKE_PACKAGE" >/dev/null 2>&1 || true

  if ! adb -s "$DEVICE_ID" shell dumpsys package "$PACKAGE_ID" \
    | grep -q "Package \[$PACKAGE_ID\]"; then
    echo "Normal release app disappeared; restoring it" >&2
    scripts/smoke_android_release_install_launch.sh "$DEVICE_ID" \
      || cleanup_status=$?
  else
    adb -s "$DEVICE_ID" shell am force-stop "$PACKAGE_ID" >/dev/null 2>&1 || true
    adb -s "$DEVICE_ID" shell monkey \
      -p "$PACKAGE_ID" \
      -c android.intent.category.LAUNCHER \
      1 >/dev/null 2>&1 || cleanup_status=$?
  fi

  local restored_first_install_time
  local restored_data_dir
  restored_first_install_time="$(package_field "$PACKAGE_ID" firstInstallTime)"
  restored_data_dir="$(package_field "$PACKAGE_ID" dataDir)"
  if [[ "$restored_first_install_time" != "$ORIGINAL_FIRST_INSTALL_TIME" ]]; then
    echo "Original app firstInstallTime changed: $ORIGINAL_FIRST_INSTALL_TIME -> $restored_first_install_time" >&2
    cleanup_status=1
  fi
  if [[ "$restored_data_dir" != "$ORIGINAL_DATA_DIR" ]]; then
    echo "Original app dataDir changed: $ORIGINAL_DATA_DIR -> $restored_data_dir" >&2
    cleanup_status=1
  fi
  if adb -s "$DEVICE_ID" shell pm list packages "$SMOKE_PACKAGE" \
    | grep -q "$SMOKE_PACKAGE"; then
    echo "Isolated Dreaming Reflection smoke package remains installed" >&2
    cleanup_status=1
  fi
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' pubspec.yaml pubspec.lock; then
    echo "Temporary sqlite3 system hook remains after smoke" >&2
    cleanup_status=1
  fi

  local release_pid
  release_pid="$(adb -s "$DEVICE_ID" shell pidof "$PACKAGE_ID" | tr -d '\r' || true)"
  if [[ -z "$release_pid" ]]; then
    echo "Normal release process is not visible after smoke cleanup" >&2
    cleanup_status=1
  else
    echo "NORMAL_RELEASE_RESTORED package=$PACKAGE_ID pid=$release_pid firstInstallTime=$restored_first_install_time dataDir=$restored_data_dir"
  fi
  echo "Dreaming Reflection device smoke log: $LOG_PATH"
  echo "Dreaming Reflection device prefs: $PREFS_PATH"

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
DART_DEFINE_ARGS=(--dart-define=SIMICHAT_DREAMING_REFLECTION_SMOKE=true)
if [[ "$SMOKE_SQLITE_RECOVERY" == "1" ]]; then
  DART_DEFINE_ARGS+=(
    --dart-define=SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERY_SMOKE=true
  )
fi
ORG_GRADLE_PROJECT_simichatApplicationId="$SMOKE_PACKAGE" \
  "$FLUTTER_BIN" --no-version-check build apk \
    --debug \
    --target-platform android-arm64 \
    "${DART_DEFINE_ARGS[@]}" \
    --no-pub

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing isolated smoke APK: $APK_PATH" >&2
  exit 1
fi

adb -s "$DEVICE_ID" install -r -t "$APK_PATH"
if ! adb -s "$DEVICE_ID" shell dumpsys package "$SMOKE_PACKAGE" \
  | grep -q "Package \[$SMOKE_PACKAGE\]"; then
  echo "Isolated smoke package was not installed as $SMOKE_PACKAGE" >&2
  exit 1
fi
if [[ "$(package_field "$PACKAGE_ID" firstInstallTime)" != "$ORIGINAL_FIRST_INSTALL_TIME" ]]; then
  echo "Original release package changed during isolated smoke installation" >&2
  exit 1
fi

adb -s "$DEVICE_ID" logcat -c
adb -s "$DEVICE_ID" shell monkey \
  -p "$SMOKE_PACKAGE" \
  -c android.intent.category.LAUNCHER \
  1 >/dev/null

if [[ "$SMOKE_SQLITE_RECOVERY" == "1" ]]; then
  for _ in $(seq 1 60); do
    adb -s "$DEVICE_ID" logcat -d >"$LOG_PATH"
    if grep -q 'SIMICHAT_DREAMING_REFLECTION_SQLITE_READY' "$LOG_PATH"; then
      break
    fi
    sleep 1
  done
  grep -q 'SIMICHAT_DREAMING_REFLECTION_SQLITE_READY' "$LOG_PATH"
  SMOKE_PID_BEFORE="$(
    adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
  )"
  [[ -n "$SMOKE_PID_BEFORE" ]]

  adb -s "$DEVICE_ID" shell am force-stop "$SMOKE_PACKAGE"
  for _ in $(seq 1 30); do
    if [[ -z "$(adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true)" ]]; then
      break
    fi
    sleep 1
  done
  [[ -z "$(adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true)" ]]
  adb -s "$DEVICE_ID" shell monkey \
    -p "$SMOKE_PACKAGE" \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null

  SMOKE_PID_AFTER=""
  for _ in $(seq 1 60); do
    SMOKE_PID_AFTER="$(
      adb -s "$DEVICE_ID" shell pidof "$SMOKE_PACKAGE" | tr -d '\r' || true
    )"
    if [[ -n "$SMOKE_PID_AFTER" && "$SMOKE_PID_AFTER" != "$SMOKE_PID_BEFORE" ]]; then
      break
    fi
    sleep 1
  done
  [[ -n "$SMOKE_PID_AFTER" ]]
  [[ "$SMOKE_PID_AFTER" != "$SMOKE_PID_BEFORE" ]]

  for _ in $(seq 1 60); do
    adb -s "$DEVICE_ID" logcat -d >"$LOG_PATH"
    if grep -q 'SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED' "$LOG_PATH"; then
      break
    fi
    sleep 1
  done
  grep -q 'SIMICHAT_DREAMING_REFLECTION_SQLITE_RECOVERED' "$LOG_PATH"
  adb -s "$DEVICE_ID" exec-out run-as "$SMOKE_PACKAGE" \
    cat shared_prefs/FlutterSharedPreferences.xml >"$PREFS_PATH"
  grep -q 'dreaming_digest_v1' "$PREFS_PATH"
  grep -q 'dreaming_digest_history_v1' "$PREFS_PATH"
  grep -q 'assistant_reflection_v1' "$PREFS_PATH"
  grep -q 'assistant_reflection_history_v1' "$PREFS_PATH"
  if grep -q 'assistant_reflection_pending_v1' "$PREFS_PATH"; then
    echo "Reflection pending remains after SQLite recovery" >&2
    exit 1
  fi
  grep 'SIMICHAT_DREAMING_REFLECTION_SQLITE_' "$LOG_PATH"
  echo "ISOLATED_DREAMING_REFLECTION_SQLITE_RECOVERY_OK package=$SMOKE_PACKAGE before=$SMOKE_PID_BEFORE after=$SMOKE_PID_AFTER"
else
  for _ in $(seq 1 60); do
    adb -s "$DEVICE_ID" logcat -d >"$LOG_PATH"
    if grep -q 'SIMICHAT_DREAMING_REFLECTION_PENDING' "$LOG_PATH"; then
      break
    fi
    sleep 1
  done
  grep -q 'SIMICHAT_DREAMING_REFLECTION_PENDING' "$LOG_PATH"

  adb -s "$DEVICE_ID" shell input keyevent KEYCODE_HOME
  sleep 2
  adb -s "$DEVICE_ID" shell monkey \
    -p "$SMOKE_PACKAGE" \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null

  for _ in $(seq 1 60); do
    adb -s "$DEVICE_ID" logcat -d >"$LOG_PATH"
    if grep -q 'SIMICHAT_DREAMING_REFLECTION_RECOVERED' "$LOG_PATH"; then
      break
    fi
    sleep 1
  done
  grep -q 'SIMICHAT_DREAMING_REFLECTION_RECOVERED' "$LOG_PATH"

  grep 'SIMICHAT_DREAMING_REFLECTION_' "$LOG_PATH"
  echo "ISOLATED_DREAMING_REFLECTION_SMOKE_OK package=$SMOKE_PACKAGE"
fi
