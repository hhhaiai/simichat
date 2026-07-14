#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-00008110-0016349A3A20A01E}}"
PRODUCTION_BUNDLE_ID="${PRODUCTION_BUNDLE_ID:-top.simitalk.aichat}"
LLDB_TARGET_BINARY="${LLDB_TARGET_BINARY:-/usr/bin/true}"
LOG_PATH="${LOG_PATH:-/tmp/simichat-ios-background-refresh-status-$(date +%Y%m%d%H%M%S).log}"
MAX_LLDB_ATTEMPTS=2
LAUNCH_JSON="$(mktemp /tmp/simichat-ios-background-refresh-launch.XXXXXX)"
PRODUCTION_APP_BEFORE=""

app_line() {
  xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null |
    awk -v bundle="$PRODUCTION_BUNDLE_ID" '$2 == bundle { print; exit }'
}

cleanup() {
  local status=$?
  set +e
  rm -f "$LAUNCH_JSON"
  local production_after
  production_after="$(app_line)"
  if [[ -z "$production_after" ]]; then
    echo "Production app is missing after iOS background refresh status check" >&2
    status=1
  elif [[ "$production_after" != "$PRODUCTION_APP_BEFORE" ]]; then
    echo "Production app identity changed after iOS background refresh status check" >&2
    status=1
  fi
  echo "iOS background refresh status log: $LOG_PATH"
  exit "$status"
}
trap cleanup EXIT

if [[ ! -x "$LLDB_TARGET_BINARY" ]]; then
  echo "An executable LLDB target binary is required: $LLDB_TARGET_BINARY" >&2
  exit 2
fi

PRODUCTION_APP_BEFORE="$(app_line)"
if [[ -z "$PRODUCTION_APP_BEFORE" ]]; then
  echo "Production app is not installed; refusing iOS background refresh status check" >&2
  exit 2
fi

launch_production_app() {
  if ! xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --timeout 30 \
    --terminate-existing \
    --json-output "$LAUNCH_JSON" \
    "$PRODUCTION_BUNDLE_ID" >/dev/null; then
    echo "iOS background refresh status launch preflight failed; unlock the device" >&2
    return 2
  fi

  PID="$(python3 - "$LAUNCH_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
process = data.get("result", {}).get("process", {})
print(process.get("processIdentifier") or process.get("pid") or "")
PY
)"
  if [[ -z "$PID" ]]; then
    echo "Unable to locate the production iOS process" >&2
    return 1
  fi
}

EXPRESSION='(long)((long (*)(void *, void *))objc_msgSend)(((void *(*)(void *, void *))objc_msgSend)((void *)objc_getClass("UIApplication"), (void *)sel_registerName("sharedApplication")), (void *)sel_registerName("backgroundRefreshStatus"))'
: >"$LOG_PATH"
PID=""
RAW_STATUS=""
for ((attempt = 1; attempt <= MAX_LLDB_ATTEMPTS; attempt += 1)); do
  launch_production_app
  ATTEMPT_LOG="$(mktemp /tmp/simichat-ios-background-refresh-lldb.XXXXXX)"
  if xcrun lldb -b \
    -o "target create $LLDB_TARGET_BINARY" \
    -o "device select $DEVICE_ID" \
    -o "device process attach -p $PID" \
    -o 'script import time, lldb; process = lldb.debugger.GetSelectedTarget().GetProcess(); deadline = time.time() + 30; [time.sleep(1) for _ in iter(lambda: process.GetState() != lldb.eStateStopped and time.time() < deadline, False)]; state_name = lldb.SBDebugger.StateAsCString(process.GetState()); print("LLDB_ATTACH_STATE", state_name); assert state_name == "stopped", f"LLDB attach did not stop the process: {state_name}"' \
    -o "expression -a false -t 5000000 -l c -- $EXPRESSION" \
    -o "process detach" \
    -o "quit" >"$ATTEMPT_LOG" 2>&1; then
    :
  fi
  {
    echo "=== LLDB ATTEMPT $attempt ==="
    cat "$ATTEMPT_LOG"
  } >>"$LOG_PATH"
  RAW_STATUS="$(
    sed -n 's/.*(long) \$[0-9][0-9]* = \(-\{0,1\}[0-9][0-9]*\).*/\1/p' "$ATTEMPT_LOG" |
      tail -1
  )"
  rm -f "$ATTEMPT_LOG"
  case "$RAW_STATUS" in
    0 | 1 | 2) break ;;
  esac
  if ((attempt < MAX_LLDB_ATTEMPTS)); then
    echo "Retrying iOS background refresh status read after LLDB interruption" >&2
  fi
done

case "$RAW_STATUS" in
  0) STATUS=restricted ;;
  1) STATUS=denied ;;
  2) STATUS=available ;;
  *)
    echo "Unable to parse UIApplication.backgroundRefreshStatus" >&2
    sed -n '1,160p' "$LOG_PATH" >&2
    exit 1
    ;;
esac

echo "IOS_BACKGROUND_REFRESH_STATUS_OK device=$DEVICE_ID bundle=$PRODUCTION_BUNDLE_ID pid=$PID raw=$RAW_STATUS status=$STATUS"
