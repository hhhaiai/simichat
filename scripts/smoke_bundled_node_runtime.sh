#!/usr/bin/env bash
set -euo pipefail

# Host-side release smoke for the exact Node binary that is copied into the
# desktop bundle. It does not resolve node/npm/npx from PATH.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${SIMICHAT_BUNDLED_NODE_PATH:-$ROOT_DIR/tools/node_runtime/bundled/macos-arm64/node}"
SERVER="$ROOT_DIR/tools/mcp_runtime/container/runtime-server.mjs"
PORT="${SIMICHAT_MCP_RUNTIME_PORT:-37651}"
SERVER_LOG="$(mktemp /tmp/simichat-bundled-node-server.XXXXXX)"
SSE_LOG="$(mktemp /tmp/simichat-bundled-node-sse.XXXXXX)"
SERVER_PID=""
SSE_PID=""
cleanup() {
  if [[ -n "$SSE_PID" ]]; then
    kill "$SSE_PID" 2>/dev/null || true
    wait "$SSE_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$SERVER_LOG" "$SSE_LOG"
}
trap cleanup EXIT

[[ -x "$NODE_BIN" ]] || { echo "bundled Node binary is not executable: $NODE_BIN" >&2; exit 1; }
[[ -f "$SERVER" ]] || { echo "MCP server script is missing: $SERVER" >&2; exit 1; }

MCP_RUNTIME_HOST=127.0.0.1 \
MCP_RUNTIME_PORT="$PORT" \
MCP_RUNTIME_WORKSPACE_ROOT="$ROOT_DIR" \
SIMICHAT_NODE_RUNTIME_KIND=desktop-bundled \
SIMICHAT_NODE_APP_MANAGED=true \
  "$NODE_BIN" "$SERVER" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 120); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo 'bundled Node server exited before health check' >&2
    cat "$SERVER_LOG" >&2 || true
    exit 1
  fi
  if health_body="$(curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null)"; then
    if grep -q '"runtime":"simichat-node-embedded"' <<<"$health_body"; then
      break
    fi
  fi
  sleep 0.1
done
health_body="$(curl -fsS "http://127.0.0.1:$PORT/health")"
printf '%s\n' "$health_body"
grep -q '"runtime":"simichat-node-embedded"' <<<"$health_body"

curl -fsS -N "http://127.0.0.1:$PORT/mcp/sse/simichat-node" >"$SSE_LOG" 2>/dev/null &
SSE_PID="$!"
for _ in $(seq 1 120); do
  if ! kill -0 "$SSE_PID" 2>/dev/null; then
    echo 'MCP SSE connection exited before endpoint event' >&2
    cat "$SSE_LOG" >&2 || true
    exit 1
  fi
  if grep -q '^event: endpoint' "$SSE_LOG"; then
    break
  fi
  sleep 0.1
done
endpoint="$(awk '/^event: endpoint/{seen=1; next} seen && /^data: /{sub(/^data: /, ""); print; exit}' "$SSE_LOG")"
[[ -n "$endpoint" ]] || { echo 'missing MCP SSE endpoint' >&2; exit 1; }

post() {
  curl -fsS -X POST "http://127.0.0.1:$PORT$endpoint" \
    -H 'content-type: application/json' \
    --data "$1" >/dev/null
}

post '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
for _ in $(seq 1 120); do
  if grep -q 'simichat.node_runtime_info' "$SSE_LOG"; then break; fi
  sleep 0.1
done
grep -q 'simichat.node_runtime_info' "$SSE_LOG"

post '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"simichat.node_runtime_info","arguments":{}}}'
for _ in $(seq 1 120); do
  if grep -Eq 'requiresHostNode.*false' "$SSE_LOG"; then break; fi
  sleep 0.1
done
grep -Eq 'requiresHostNode.*false' "$SSE_LOG"
grep -Eq 'requiresHostNpx.*false' "$SSE_LOG"
grep -Eq 'requiresDocker.*false' "$SSE_LOG"

echo 'SIMICHAT_DESKTOP_BUNDLED_NODE_PROCESS_READY'
