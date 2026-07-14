#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export TRIGGER_MODE=natural
export SMOKE_INITIAL_DELAY_SECONDS="${SMOKE_INITIAL_DELAY_SECONDS:-30}"
export RESULT_WAIT_SECONDS="${RESULT_WAIT_SECONDS:-240}"

exec scripts/smoke_device_android_background_dreaming.sh "$@"
