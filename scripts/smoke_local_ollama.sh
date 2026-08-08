#!/usr/bin/env bash
set -euo pipefail

# 本脚本只验证已经运行的 Ollama，不会启动、停止或修改本机模型服务。
BASE_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
MODEL="${OLLAMA_MODEL:-gemma4}"
TIMEOUT="${OLLAMA_SMOKE_TIMEOUT_SECONDS:-120}"
BASE_URL="${BASE_URL%/}"

if [[ -z "$BASE_URL" || -z "$MODEL" ]]; then
  echo "LOCAL_OLLAMA_SMOKE_FAIL: OLLAMA_BASE_URL 和 OLLAMA_MODEL 不能为空" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

tags_file="$tmp_dir/tags.json"
response_file="$tmp_dir/response.ndjson"

echo "LOCAL_OLLAMA_BASE_URL=$BASE_URL"
echo "LOCAL_OLLAMA_MODEL=$MODEL"

if ! curl -fsS --max-time 15 "$BASE_URL/api/tags" >"$tags_file"; then
  echo "LOCAL_OLLAMA_SMOKE_FAIL: 无法连接 Ollama /api/tags，请先启动服务并检查 Base URL" >&2
  exit 10
fi

if ! python3 - "$tags_file" "$MODEL" <<'PY'
import json
import sys

tags_path, requested = sys.argv[1:]
with open(tags_path, encoding='utf-8') as handle:
    payload = json.load(handle)

available = {
    str(item.get('name', '')).strip()
    for item in payload.get('models', [])
    if isinstance(item, dict) and str(item.get('name', '')).strip()
}

def comparable(value: str) -> str:
    return value[:-7] if value.endswith(':latest') else value

if requested not in available and comparable(requested) not in {
    comparable(item) for item in available
}:
    print('LOCAL_OLLAMA_SMOKE_FAIL: requested model is not installed', file=sys.stderr)
    print('LOCAL_OLLAMA_AVAILABLE_MODELS=' + ','.join(sorted(available)))
    raise SystemExit(11)

print('LOCAL_OLLAMA_TAGS_OK')
PY
then
  exit 11
fi

request_body="$tmp_dir/request.json"
python3 - "$request_body" "$MODEL" <<'PY'
import json
import sys

path, model = sys.argv[1:]
with open(path, 'w', encoding='utf-8') as handle:
    json.dump({
        'model': model,
        'messages': [
            {'role': 'user', 'content': 'Reply with exactly LOCAL_MODEL_SMOKE_OK.'}
        ],
        'stream': True,
    }, handle)
PY

curl_args=(
  -fsS
  --max-time "$TIMEOUT"
  -H 'Content-Type: application/json'
  --data-binary "@$request_body"
  "$BASE_URL/api/chat"
)
if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
  curl_args=(-H "Authorization: Bearer ${OLLAMA_API_KEY}" "${curl_args[@]}")
fi

if ! curl "${curl_args[@]}" >"$response_file"; then
  echo "LOCAL_OLLAMA_SMOKE_FAIL: /api/chat 请求失败或超时" >&2
  exit 12
fi

python3 - "$response_file" <<'PY'
import json
import sys

path = sys.argv[1]
content = []
thinking = []
done = False
lines = 0
with open(path, encoding='utf-8') as handle:
    for raw in handle:
        line = raw.strip()
        if not line:
            continue
        lines += 1
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        message = item.get('message') or {}
        if isinstance(message, dict):
            if message.get('content'):
                content.append(str(message['content']))
            if message.get('thinking'):
                thinking.append(str(message['thinking']))
        done = done or item.get('done') is True

text = ''.join(content)
if not done or not (text.strip() or ''.join(thinking).strip()):
    print('LOCAL_OLLAMA_SMOKE_FAIL: NDJSON 流没有完成且没有有效模型输出', file=sys.stderr)
    raise SystemExit(13)

print(f'LOCAL_OLLAMA_CHAT_OK lines={lines} content_chars={len(text)} thinking_chars={len("".join(thinking))}')
print('LOCAL_OLLAMA_SMOKE_OK')
PY
