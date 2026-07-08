#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/tools/mcp_runtime/container"
IMAGE="${SIMICHAT_MCP_RUNTIME_IMAGE:-simichat-mcp-runtime:local}"
NAME="${SIMICHAT_MCP_RUNTIME_NAME:-simichat-mcp-runtime}"
PORT="${SIMICHAT_MCP_RUNTIME_PORT:-37651}"
BASE_IMAGE="${SIMICHAT_MCP_RUNTIME_BASE_IMAGE:-node:22-alpine}"

container_cli() {
  if [[ -n "${CONTAINER_CLI:-}" ]]; then
    printf '%s\n' "$CONTAINER_CLI"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    printf 'docker\n'
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    printf 'podman\n'
    return 0
  fi
  echo 'Docker or Podman is required to run the PC MCP runtime container.' >&2
  return 1
}

usage() {
  cat <<USAGE
Usage: scripts/mcp_runtime_container.sh <build|start|stop|restart|status|logs|smoke>

Environment:
  CONTAINER_CLI                 docker or podman override
  SIMICHAT_MCP_RUNTIME_IMAGE    default: simichat-mcp-runtime:local
  SIMICHAT_MCP_RUNTIME_NAME     default: simichat-mcp-runtime
  SIMICHAT_MCP_RUNTIME_PORT     default: 37651
  SIMICHAT_MCP_RUNTIME_BASE_IMAGE default: node:22-alpine

The container carries Node itself. This script never calls host node/npm/npx.
USAGE
}

cmd="${1:-status}"

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  usage
  exit 0
fi

cli="$(container_cli)"

container_running() {
  [[ "$("$cli" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" == "true" ]]
}

wait_for_sse_endpoint() {
  local sse_log="$1"
  local endpoint=""
  for _ in $(seq 1 100); do
    endpoint="$(awk '/^event: endpoint/{seen=1; next} seen && /^data: /{sub(/^data: /, ""); print; exit}' "$sse_log" || true)"
    if [[ -n "$endpoint" ]]; then
      printf '%s\n' "$endpoint"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

post_mcp_message() {
  local endpoint="$1"
  local payload="$2"
  local target
  if [[ "$endpoint" == http://* || "$endpoint" == https://* ]]; then
    target="$endpoint"
  else
    target="http://127.0.0.1:$PORT$endpoint"
  fi
  curl -fsS -X POST "$target" \
    -H 'content-type: application/json' \
    --data "$payload" >/dev/null
}

smoke_runtime() {
  SMOKE_WAS_RUNNING=false
  if container_running; then
    SMOKE_WAS_RUNNING=true
  fi

  "$0" start

  SMOKE_SSE_LOG=""
  SMOKE_CURL_PID=""
  cleanup_smoke() {
    if [[ -n "${SMOKE_CURL_PID:-}" ]]; then
      kill "$SMOKE_CURL_PID" >/dev/null 2>&1 || true
      wait "$SMOKE_CURL_PID" 2>/dev/null || true
    fi
    if [[ -n "${SMOKE_SSE_LOG:-}" ]]; then
      rm -f "$SMOKE_SSE_LOG"
    fi
    if [[ "${SMOKE_WAS_RUNNING:-false}" != "true" ]]; then
      "$0" stop >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_smoke EXIT

  local health_ok=false
  for _ in $(seq 1 100); do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>/dev/null; then
      health_ok=true
      break
    fi
    sleep 0.1
  done
  if [[ "$health_ok" != "true" ]]; then
    echo 'MCP runtime health check did not become ready.' >&2
    exit 1
  fi

  SMOKE_SSE_LOG="$(mktemp /tmp/simichat-mcp-sse.XXXXXX)"
  curl -fsS -N "http://127.0.0.1:$PORT/mcp/sse/simichat-node" >"$SMOKE_SSE_LOG" 2>/dev/null &
  SMOKE_CURL_PID="$!"

  local endpoint
  if ! endpoint="$(wait_for_sse_endpoint "$SMOKE_SSE_LOG")"; then
    echo 'MCP SSE endpoint event was not received.' >&2
    cat "$SMOKE_SSE_LOG" >&2 || true
    exit 1
  fi

  post_mcp_message "$endpoint" '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
  for _ in $(seq 1 100); do
    if grep -q 'simichat.node_runtime_info' "$SMOKE_SSE_LOG"; then
      break
    fi
    sleep 0.1
  done
  grep -q 'simichat.node_runtime_info' "$SMOKE_SSE_LOG"

  post_mcp_message "$endpoint" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"simichat.echo","arguments":{"text":"container smoke"}}}'
  for _ in $(seq 1 100); do
    if grep -q 'container smoke' "$SMOKE_SSE_LOG"; then
      break
    fi
    sleep 0.1
  done
  grep -q 'container smoke' "$SMOKE_SSE_LOG"

  post_mcp_message "$endpoint" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"simichat.fs_list","arguments":{"path":".","maxEntries":20}}}'
  for _ in $(seq 1 100); do
    if grep -q 'runtime-server.mjs' "$SMOKE_SSE_LOG"; then
      break
    fi
    sleep 0.1
  done
  grep -q 'runtime-server.mjs' "$SMOKE_SSE_LOG"

  post_mcp_message "$endpoint" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"simichat.fetch_text","arguments":{"url":"http://127.0.0.1:37651/health","maxBytes":4096}}}'
  for _ in $(seq 1 100); do
    if grep -q 'simichat-node-container' "$SMOKE_SSE_LOG"; then
      break
    fi
    sleep 0.1
  done
  grep -q 'simichat-node-container' "$SMOKE_SSE_LOG"

  echo 'SMOKE_HEALTH_OK'
  echo 'SMOKE_TOOL_LIST_OK'
  echo 'SMOKE_TOOL_CALL_OK'
  echo 'SMOKE_FS_TOOL_OK'
  echo 'SMOKE_FETCH_TOOL_OK'
}

case "$cmd" in
  build)
    "$cli" build --build-arg "SIMICHAT_MCP_RUNTIME_BASE_IMAGE=$BASE_IMAGE" -t "$IMAGE" "$RUNTIME_DIR"
    ;;
  start)
    if ! "$cli" image inspect "$IMAGE" >/dev/null 2>&1; then
      "$cli" build --build-arg "SIMICHAT_MCP_RUNTIME_BASE_IMAGE=$BASE_IMAGE" -t "$IMAGE" "$RUNTIME_DIR"
    fi
    if "$cli" container inspect "$NAME" >/dev/null 2>&1; then
      if [[ "$("$cli" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" == "true" ]]; then
        echo "SimiChat MCP runtime is already running: http://127.0.0.1:$PORT/mcp/sse/simichat-node"
        exit 0
      fi
      "$cli" rm "$NAME" >/dev/null
    fi
    "$cli" run -d \
      --name "$NAME" \
      --label top.simitalk.aichat.mcp-runtime=true \
      -p "127.0.0.1:$PORT:37651" \
      "$IMAGE" >/dev/null
    echo "SimiChat MCP runtime started: http://127.0.0.1:$PORT/mcp/sse/simichat-node"
    ;;
  stop)
    if "$cli" container inspect "$NAME" >/dev/null 2>&1; then
      "$cli" rm -f "$NAME" >/dev/null
      echo "SimiChat MCP runtime stopped."
    else
      echo "SimiChat MCP runtime is not running."
    fi
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  status)
    if "$cli" container inspect "$NAME" >/dev/null 2>&1; then
      "$cli" ps --filter "name=^/${NAME}$"
      echo "MCP SSE: http://127.0.0.1:$PORT/mcp/sse/simichat-node"
      echo "Health:  http://127.0.0.1:$PORT/health"
    else
      echo "SimiChat MCP runtime container not created. Run: scripts/mcp_runtime_container.sh start"
    fi
    ;;
  logs)
    "$cli" logs -f "$NAME"
    ;;
  smoke)
    smoke_runtime
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
