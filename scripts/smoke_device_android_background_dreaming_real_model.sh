#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
MODEL_CONFIG_FILE="${MODEL_CONFIG_FILE:-}"
REMOTE_MODEL_PREFLIGHT_ATTEMPTS="${REMOTE_MODEL_PREFLIGHT_ATTEMPTS:-3}"
SMOKE_PACKAGE="top.simitalk.aichat.backgroundmodelsmoke"
CROSS_DAY_STATE_PATH=".omx/state/android-background-dreaming-cross-day.state"
CURL_CONFIG_FILE=""
REQUEST_FILE=""
RESPONSE_FILE=""
CROSS_DAY_EXPECTED_DAY_KEY=""

remote_model_config_mode() {
  local path="$1"
  stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null
}

cleanup() {
  local status=$?
  trap - EXIT
  rm -f \
    "${CURL_CONFIG_FILE:-}" \
    "${REQUEST_FILE:-}" \
    "${RESPONSE_FILE:-}"
  exit "$status"
}
trap cleanup EXIT

if [[ -z "$MODEL_CONFIG_FILE" || \
  ! -f "$MODEL_CONFIG_FILE" || \
  ! -s "$MODEL_CONFIG_FILE" ]]; then
  echo "MODEL_CONFIG_FILE must point to the user-authorized remote model config" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "curl and jq are required for the remote model smoke" >&2
  exit 1
fi
if [[ ! "$REMOTE_MODEL_PREFLIGHT_ATTEMPTS" =~ ^[1-5]$ ]]; then
  echo "REMOTE_MODEL_PREFLIGHT_ATTEMPTS must be between 1 and 5" >&2
  exit 2
fi
MODEL_CONFIG_MODE="$(remote_model_config_mode "$MODEL_CONFIG_FILE")"
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

API_BASE_URL="$(jq -r '.baseUrl | sub("/+$"; "")' "$MODEL_CONFIG_FILE")"
MODEL_NAME="$(jq -r '.model' "$MODEL_CONFIG_FILE")"
API_KEY="$(jq -r '.apiKey' "$MODEL_CONFIG_FILE")"
if [[ ! "$API_KEY" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Remote API key contains unsupported characters" >&2
  exit 2
fi

if [[ -f "$CROSS_DAY_STATE_PATH" ]]; then
  CROSS_DAY_STATUS_BEFORE="$(
    ./scripts/smoke_device_android_background_dreaming_cross_day.sh status
  )"
  grep -q 'job_0_state=waiting' <<<"$CROSS_DAY_STATUS_BEFORE"
  CROSS_DAY_EXPECTED_DAY_KEY="$(
    sed -n 's/.*expectedDayKey=\([^ ]*\).*/\1/p' \
      <<<"$CROSS_DAY_STATUS_BEFORE"
  )"
  [[ -n "$CROSS_DAY_EXPECTED_DAY_KEY" ]]
fi

umask 077
CURL_CONFIG_FILE="$(mktemp /tmp/simichat-remote-model-curl.XXXXXX)"
REQUEST_FILE="$(mktemp /tmp/simichat-remote-model-request.XXXXXX)"
RESPONSE_FILE="$(mktemp /tmp/simichat-remote-model-response.XXXXXX)"
printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" \
  >"$CURL_CONFIG_FILE"
unset API_KEY
jq \
  --null-input \
  --arg model "$MODEL_NAME" \
  '{
    model: $model,
    messages: [{role: "user", content: "Reply with one short sentence."}],
    stream: false
  }' >"$REQUEST_FILE"

REMOTE_MODEL_READY=0
HTTP_STATUS="000"
for ((attempt = 1; attempt <= REMOTE_MODEL_PREFLIGHT_ATTEMPTS; attempt++)); do
  : >"$RESPONSE_FILE"
  set +e
  HTTP_STATUS="$(
    curl \
      --config "$CURL_CONFIG_FILE" \
      --silent \
      --show-error \
      --output "$RESPONSE_FILE" \
      --write-out '%{http_code}' \
      --header 'Content-Type: application/json' \
      --data-binary "@$REQUEST_FILE" \
      "$API_BASE_URL/v1/chat/completions"
  )"
  CURL_STATUS=$?
  set -e

  if [[ "$CURL_STATUS" == "0" && "$HTTP_STATUS" == "200" ]] && \
    jq -e '.choices[0].message.content | strings | length > 0' \
      "$RESPONSE_FILE" >/dev/null 2>&1; then
    REMOTE_MODEL_READY=1
    echo "REMOTE_MODEL_API_READY model=$MODEL_NAME attempts=$attempt"
    break
  fi

  RETRYABLE=0
  case "$HTTP_STATUS" in
    401|408|429|5??) RETRYABLE=1 ;;
  esac
  if [[ "$CURL_STATUS" != "0" || "$HTTP_STATUS" == "200" ]]; then
    RETRYABLE=1
  fi
  if [[ "$attempt" -lt "$REMOTE_MODEL_PREFLIGHT_ATTEMPTS" && \
    "$RETRYABLE" == "1" ]]; then
    echo "REMOTE_MODEL_API_RETRY attempt=$attempt status=$HTTP_STATUS" >&2
    sleep "$((attempt * 2))"
    continue
  fi
  echo "REMOTE_MODEL_API_FAILED status=$HTTP_STATUS attempts=$attempt" >&2
  exit 1
done
[[ "$REMOTE_MODEL_READY" == "1" ]]

SMOKE_PACKAGE="$SMOKE_PACKAGE" \
SMOKE_REAL_MODEL=1 \
SMOKE_MODEL_CONFIG_FILE="$MODEL_CONFIG_FILE" \
TRIGGER_MODE=natural \
BACKGROUND_PROCESS_MODE=kill \
SMOKE_INITIAL_DELAY_SECONDS="${SMOKE_INITIAL_DELAY_SECONDS:-30}" \
RESULT_WAIT_SECONDS="${RESULT_WAIT_SECONDS:-420}" \
  ./scripts/smoke_device_android_background_dreaming.sh "$DEVICE_ID"

if [[ -n "$CROSS_DAY_EXPECTED_DAY_KEY" ]]; then
  CROSS_DAY_STATUS_AFTER="$(
    ./scripts/smoke_device_android_background_dreaming_cross_day.sh status
  )"
  grep -q 'job_0_state=waiting' <<<"$CROSS_DAY_STATUS_AFTER"
  grep -q "expectedDayKey=$CROSS_DAY_EXPECTED_DAY_KEY" \
    <<<"$CROSS_DAY_STATUS_AFTER"
  echo "$CROSS_DAY_STATUS_AFTER"
fi

echo "ANDROID_BACKGROUND_DREAMING_REAL_MODEL_OK package=$SMOKE_PACKAGE model=$MODEL_NAME generationMode=model"
