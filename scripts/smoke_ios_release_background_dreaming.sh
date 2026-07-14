#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-00008110-0016349A3A20A01E}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PRODUCTION_BUNDLE_ID="${PRODUCTION_BUNDLE_ID:-top.simitalk.aichat}"
SMOKE_BUNDLE_ID="${SMOKE_BUNDLE_ID:-top.simitalk.aichat.iosbackgroundsmoke}"
PRODUCTION_TASK_IDENTIFIER="top.simitalk.aichat.dreaming.processing"
TASK_IDENTIFIER="${SMOKE_TASK_IDENTIFIER:-$SMOKE_BUNDLE_ID.dreaming.processing}"
APP_PATH="${APP_PATH:-build/ios/iphoneos/Runner.app}"
RESULT_SOURCE="Documents/ai_chat/ios_background_dreaming_smoke"
RESULT_FILE_NAME="ios-background-dreaming-smoke.json"
RESULT_PATH="${RESULT_PATH:-/tmp/simichat-ios-background-dreaming-result-$(date +%Y%m%d%H%M%S).json}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-ios-background-dreaming-$(date +%Y%m%d%H%M%S).log}"
VERIFY_LOG_PATH="${VERIFY_LOG_PATH:-/tmp/simichat-ios-background-dreaming-verify-$(date +%Y%m%d%H%M%S).log}"
LLDB_LOG_PATH="${LLDB_LOG_PATH:-/tmp/simichat-ios-background-dreaming-lldb-$(date +%Y%m%d%H%M%S).log}"

if [[ "$SMOKE_BUNDLE_ID" == "$PRODUCTION_BUNDLE_ID" ]]; then
  echo "Refusing to use the production bundle as the iOS background smoke bundle" >&2
  exit 2
fi
if [[ "$SMOKE_BUNDLE_ID" != "$PRODUCTION_BUNDLE_ID".* ]]; then
  echo "The iOS background smoke bundle must use the production sub-namespace" >&2
  exit 2
fi
if [[ "$TASK_IDENTIFIER" != "$SMOKE_BUNDLE_ID".* ]]; then
  echo "The iOS background smoke task must use the smoke bundle sub-namespace" >&2
  exit 2
fi

source scripts/lib/release_pubspec_hook.sh

PROJECT_FILE="ios/Runner.xcodeproj/project.pbxproj"
APP_DELEGATE_FILE="ios/Runner/AppDelegate.swift"
INFO_PLIST_FILE="ios/Runner/Info.plist"
PROJECT_BACKUP="$(mktemp /tmp/simichat-ios-bg-project.XXXXXX)"
APP_DELEGATE_BACKUP="$(mktemp /tmp/simichat-ios-bg-app-delegate.XXXXXX)"
INFO_PLIST_BACKUP="$(mktemp /tmp/simichat-ios-bg-info-plist.XXXXXX)"
cp "$PROJECT_FILE" "$PROJECT_BACKUP"
cp "$APP_DELEGATE_FILE" "$APP_DELEGATE_BACKUP"
cp "$INFO_PLIST_FILE" "$INFO_PLIST_BACKUP"
CONSOLE_PID=""
VERIFY_CONSOLE_PID=""
SMOKE_PID=""
PRODUCTION_APP_BEFORE=""
RESULT_DIR=""

resolve_core_device() {
  local requested="$1"
  local device_info
  device_info="$(mktemp /tmp/simichat-ios-bg-device.XXXXXX)"
  if xcrun devicectl device info details --device "$requested" --json-output "$device_info" >/dev/null 2>&1; then
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
print(
    result.get("identifier")
    or result.get("hardwareProperties", {}).get("udid")
    or result.get("deviceProperties", {}).get("name")
    or sys.argv[2]
)
PY
)"
    if [[ -n "$resolved" ]]; then
      requested="$resolved"
    fi
  fi
  rm -f "$device_info"
  printf '%s\n' "$requested"
}

app_line() {
  local bundle_id="$1"
  xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null | awk -v bundle="$bundle_id" '$2 == bundle { print; exit }'
}

copy_smoke_result() {
  rm -rf "$RESULT_DIR"
  mkdir -p "$RESULT_DIR"
  xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer --domain-identifier "$SMOKE_BUNDLE_ID" --source "$RESULT_SOURCE" --destination "$RESULT_DIR" >/dev/null 2>&1
}

find_result_file() {
  find "$RESULT_DIR" -name "$RESULT_FILE_NAME" -type f | head -1
}

result_value() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
value = data.get(sys.argv[2])
print("" if value is None else value)
PY
}

launch_app() {
  local bundle_id="$1"
  local terminate_existing="${2:-0}"
  local launch_json
  launch_json="$(mktemp /tmp/simichat-ios-bg-launch.XXXXXX)"
  local args=(
    xcrun devicectl device process launch
    --device "$DEVICE_ID"
    --timeout 30
    --json-output "$launch_json"
  )
  if [[ "$terminate_existing" == "1" ]]; then
    args+=(--terminate-existing)
  fi
  args+=("$bundle_id")
  "${args[@]}" >/dev/null
  python3 - "$launch_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
process = data.get("result", {}).get("process", {})
print(process.get("processIdentifier") or process.get("pid") or "")
PY
  rm -f "$launch_json"
}

terminate_runner_processes() {
  local pids
  pids="$(
    xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null | awk '/\/Runner\.app\/Runner/ {print $1}'
  )"
  for pid in ${pids:-}; do
    xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$pid" --kill --timeout 10 >/dev/null 2>&1 || true
  done
}

uninstall_smoke() {
  if [[ -n "$(app_line "$SMOKE_BUNDLE_ID")" ]]; then
    xcrun devicectl device uninstall app --device "$DEVICE_ID" "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local status=$?
  set +e
  if [[ -n "$CONSOLE_PID" ]]; then
    kill "$CONSOLE_PID" >/dev/null 2>&1 || true
    wait "$CONSOLE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$VERIFY_CONSOLE_PID" ]]; then
    kill "$VERIFY_CONSOLE_PID" >/dev/null 2>&1 || true
    wait "$VERIFY_CONSOLE_PID" >/dev/null 2>&1 || true
  fi
  uninstall_smoke
  if [[ -n "$RESULT_DIR" ]]; then
    rm -rf "$RESULT_DIR"
  fi
  cp "$PROJECT_BACKUP" "$PROJECT_FILE"
  cp "$APP_DELEGATE_BACKUP" "$APP_DELEGATE_FILE"
  cp "$INFO_PLIST_BACKUP" "$INFO_PLIST_FILE"
  rm -f "$PROJECT_BACKUP" "$APP_DELEGATE_BACKUP" "$INFO_PLIST_BACKUP"
  simichat_release_pubspec_restore

  local production_after
  production_after="$(app_line "$PRODUCTION_BUNDLE_ID")"
  if [[ -z "$production_after" ]]; then
    echo "Production app is missing after iOS background smoke cleanup" >&2
    status=1
  elif [[ "$production_after" != "$PRODUCTION_APP_BEFORE" ]]; then
    echo "Production app identity changed after iOS background smoke cleanup" >&2
    status=1
  else
    xcrun devicectl device process launch --device "$DEVICE_ID" "$PRODUCTION_BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$(app_line "$SMOKE_BUNDLE_ID")" ]]; then
    echo "iOS background smoke bundle remains installed" >&2
    status=1
  fi
  if grep -Eq 'sqlite3\.source|source:[[:space:]]*system' pubspec.yaml pubspec.lock; then
    echo "Temporary sqlite hook remains after iOS background smoke" >&2
    status=1
  fi
  echo "iOS background Dreaming log: $LOG_PATH"
  echo "iOS background Dreaming verify log: $VERIFY_LOG_PATH"
  echo "iOS background Dreaming LLDB log: $LLDB_LOG_PATH"
  echo "iOS background Dreaming result: $RESULT_PATH"
  exit "$status"
}
trap cleanup EXIT

DEVICE_ID="$(resolve_core_device "$DEVICE_ID")"
PRODUCTION_APP_BEFORE="$(app_line "$PRODUCTION_BUNDLE_ID")"
if [[ -z "$PRODUCTION_APP_BEFORE" ]]; then
  echo "Production app is not installed; refusing isolated iOS background smoke" >&2
  exit 2
fi
if ! xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$PRODUCTION_BUNDLE_ID" >/dev/null 2>&1; then
  echo "iOS background smoke launch preflight failed; unlock the device" >&2
  exit 2
fi
echo "iOS background smoke launch preflight passed"

uninstall_smoke
terminate_runner_processes

python3 - \
  "$PROJECT_FILE" \
  "$PRODUCTION_BUNDLE_ID" \
  "$SMOKE_BUNDLE_ID" \
  "$APP_DELEGATE_FILE" \
  "$INFO_PLIST_FILE" \
  "$PRODUCTION_TASK_IDENTIFIER" \
  "$TASK_IDENTIFIER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
production = sys.argv[2]
smoke = sys.argv[3]
source = path.read_text()
needle = f"PRODUCT_BUNDLE_IDENTIFIER = {production};"
count = source.count(needle)
if count != 3:
    raise SystemExit(f"expected 3 production Runner bundle settings, found {count}")
path.write_text(source.replace(needle, f"PRODUCT_BUNDLE_IDENTIFIER = {smoke};"))

production_task = sys.argv[6]
smoke_task = sys.argv[7]
for file_name in (sys.argv[4], sys.argv[5]):
    task_path = Path(file_name)
    task_source = task_path.read_text()
    count = task_source.count(production_task)
    if count != 1:
        raise SystemExit(
            f"expected 1 production task identifier in {file_name}, found {count}"
        )
    task_path.write_text(task_source.replace(production_task, smoke_task))
PY

simichat_release_pubspec_setup 0 >/tmp/simichat-ios-background-dreaming-pub-get.log
"$FLUTTER_BIN" --no-version-check build ios --release --no-pub \
  --dart-define=SIMICHAT_IOS_BACKGROUND_DREAMING_SMOKE=true \
  --dart-define=SIMICHAT_IOS_BACKGROUND_DREAMING_TASK_IDENTIFIER="$TASK_IDENTIFIER"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing iOS background smoke app: $APP_PATH" >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")" != "$SMOKE_BUNDLE_ID" ]]; then
  echo "Built iOS background smoke app has the wrong bundle id" >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :BGTaskSchedulerPermittedIdentifiers' "$APP_PATH/Info.plist" | grep -Fq "$TASK_IDENTIFIER"

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >/dev/null

RESULT_DIR="$(mktemp -d /tmp/simichat-ios-bg-result.XXXXXX)"
SMOKE_PID="$(launch_app "$SMOKE_BUNDLE_ID" 1)"
if [[ -z "$SMOKE_PID" ]]; then
  echo "Unable to locate iOS background smoke process" >&2
  exit 1
fi

result_file=""
for _ in $(seq 1 90); do
  if copy_smoke_result; then
    result_file="$(find_result_file)"
    if [[ -n "$result_file" && "$(result_value "$result_file" marker)" == "SIMICHAT_IOS_BACKGROUND_DREAMING_READY" ]]; then
      cp "$result_file" "$LOG_PATH"
      break
    fi
  fi
  sleep 1
done
if [[ ! -f "$LOG_PATH" || "$(result_value "$LOG_PATH" marker)" != "SIMICHAT_IOS_BACKGROUND_DREAMING_READY" ]]; then
  echo "Timed out waiting for iOS background Dreaming ready file" >&2
  exit 1
fi
if [[ "$(result_value "$LOG_PATH" scheduledTasks)" != *"$TASK_IDENTIFIER"* ]]; then
  refresh_status="$(result_value "$LOG_PATH" backgroundRefreshStatus)"
  echo "iOS background Dreaming task is not pending in BGTaskScheduler; Background App Refresh status=$refresh_status" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

# Keep the isolated release app foreground while LLDB invokes the private
# simulator. The timeout disables LLDB's default retry with all threads, which
# can otherwise wait indefinitely when the expression cannot complete.
SIMULATE_EXPRESSION="(void)((void (*)(void *, void *, void *))objc_msgSend)(((void *(*)(void *, void *))objc_msgSend)((void *)objc_getClass(\"BGTaskScheduler\"), (void *)sel_registerName(\"sharedScheduler\")), (void *)sel_registerName(\"_simulateLaunchForTaskWithIdentifier:\"), ((void *(*)(void *, void *, const char *))objc_msgSend)((void *)objc_getClass(\"NSString\"), (void *)sel_registerName(\"stringWithUTF8String:\"), \"$TASK_IDENTIFIER\"))"
xcrun lldb -b \
  -o "target create $APP_PATH/Runner" \
  -o "device select $DEVICE_ID" \
  -o "device process attach -p $SMOKE_PID" \
  -o 'script import time, lldb; process = lldb.debugger.GetSelectedTarget().GetProcess(); deadline = time.time() + 30; [time.sleep(1) for _ in iter(lambda: process.GetState() != lldb.eStateStopped and time.time() < deadline, False)]; state_name = lldb.SBDebugger.StateAsCString(process.GetState()); print("LLDB_ATTACH_STATE", state_name); assert state_name == "stopped", f"LLDB attach did not stop the process: {state_name}"' \
  -o "expression -a false -t 5000000 -l c -- $SIMULATE_EXPRESSION" \
  -o "process detach" \
  -o "quit" >"$LLDB_LOG_PATH" 2>&1

for _ in $(seq 1 120); do
  if copy_smoke_result; then
    result_file="$(find_result_file)"
    if [[ -n "$result_file" && "$(result_value "$result_file" marker)" == "SIMICHAT_IOS_BACKGROUND_DREAMING_RESULT" ]]; then
      cp "$result_file" "$RESULT_PATH"
      break
    fi
  fi
  sleep 1
done
if [[ ! -f "$RESULT_PATH" ]]; then
  echo "Timed out waiting for iOS background Dreaming result file" >&2
  exit 1
fi
[[ "$(result_value "$RESULT_PATH" status)" == "completed" ]]
[[ "$(result_value "$RESULT_PATH" digestDayKey)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
[[ "$(result_value "$RESULT_PATH" reflectionDayKey)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]

xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$SMOKE_PID" --kill --timeout 10 >/dev/null 2>&1 || true
SMOKE_PID="$(launch_app "$SMOKE_BUNDLE_ID" 1)"
for _ in $(seq 1 60); do
  if copy_smoke_result; then
    result_file="$(find_result_file)"
    if [[ -n "$result_file" && "$(result_value "$result_file" marker)" == "SIMICHAT_IOS_BACKGROUND_DREAMING_VERIFIED" ]]; then
      cp "$result_file" "$VERIFY_LOG_PATH"
      break
    fi
  fi
  sleep 1
done
[[ -f "$VERIFY_LOG_PATH" ]]
[[ "$(result_value "$VERIFY_LOG_PATH" marker)" == "SIMICHAT_IOS_BACKGROUND_DREAMING_VERIFIED" ]]

cat "$RESULT_PATH"
cat "$VERIFY_LOG_PATH"
echo "ISOLATED_IOS_BACKGROUND_DREAMING_SMOKE_OK bundle=$SMOKE_BUNDLE_ID"
