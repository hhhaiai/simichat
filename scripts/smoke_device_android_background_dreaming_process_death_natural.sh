#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export TRIGGER_MODE=natural
export BACKGROUND_PROCESS_MODE=kill
export SMOKE_INITIAL_DELAY_SECONDS="${SMOKE_INITIAL_DELAY_SECONDS:-30}"
export PROCESS_KILL_SETTLE_SECONDS="${PROCESS_KILL_SETTLE_SECONDS:-0}"
export RESULT_WAIT_SECONDS="${RESULT_WAIT_SECONDS:-900}"

exec scripts/smoke_device_android_background_dreaming.sh "$@"
