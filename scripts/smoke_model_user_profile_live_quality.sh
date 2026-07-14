#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL_CONFIG_FILE="${MODEL_CONFIG_FILE:-}"
SIMICHAT_LIVE_PROFILE_MODEL_RUNS="${SIMICHAT_LIVE_PROFILE_MODEL_RUNS:-3}"

config_mode() {
  local path="$1"
  stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null
}

if [[ -z "$MODEL_CONFIG_FILE" || ! -s "$MODEL_CONFIG_FILE" ]]; then
  echo "MODEL_CONFIG_FILE must point to a non-empty remote model config" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for the remote model profile quality gate" >&2
  exit 1
fi

MODEL_CONFIG_MODE="$(config_mode "$MODEL_CONFIG_FILE")"
if [[ "$MODEL_CONFIG_MODE" != "600" && "$MODEL_CONFIG_MODE" != "400" ]]; then
  echo "MODEL_CONFIG_FILE permissions must be 600 or 400" >&2
  exit 2
fi
if ! jq -e '
  .protocol == "openai_chat" and
  (.baseUrl | type == "string" and length > 0) and
  (.apiKey | type == "string" and length > 0) and
  (.model | type == "string" and length > 0)
' "$MODEL_CONFIG_FILE" >/dev/null; then
  echo "MODEL_CONFIG_FILE is not a valid remote OpenAI model config" >&2
  exit 2
fi
if [[ ! "$SIMICHAT_LIVE_PROFILE_MODEL_RUNS" =~ ^[1-5]$ ]]; then
  echo "SIMICHAT_LIVE_PROFILE_MODEL_RUNS must be between 1 and 5" >&2
  exit 2
fi

export MODEL_CONFIG_FILE
export SIMICHAT_LIVE_PROFILE_MODEL_RUNS

flutter --no-version-check test --no-pub --no-test-assets -r expanded \
  tool/model_user_profile_live_quality_test.dart \
  --plain-name 'remote OpenAI-compatible model produces safe grounded profile candidates'
