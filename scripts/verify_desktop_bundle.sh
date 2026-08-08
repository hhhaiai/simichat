#!/usr/bin/env bash
set -euo pipefail

# Verify a built desktop package, then run the MCP process smoke against the
# exact binary inside that package. This never substitutes the host PATH node.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
case "$TARGET" in
  macos)
    APP_ROOT="${2:-$ROOT_DIR/build/macos/Build/Products/Release/ai_chat_app.app}"
    NODE_BIN="$APP_ROOT/Contents/Resources/node_runtime/macos-arm64/node"
    ;;
  linux)
    BUNDLE_ROOT="${2:-$ROOT_DIR/build/linux/x64/release/bundle}"
    NODE_BIN="$BUNDLE_ROOT/node_runtime/linux-x64/node"
    ;;
  windows)
    BUNDLE_ROOT="${2:-$ROOT_DIR/build/windows/x64/runner/Release}"
    NODE_BIN="$BUNDLE_ROOT/node_runtime/windows-x64/node.exe"
    ;;
  *)
    echo "Usage: $0 macos|linux|windows [package-root]" >&2
    exit 2
    ;;
esac

if [[ ! -x "$NODE_BIN" ]]; then
  echo "Bundled Node binary is missing or not executable: $NODE_BIN" >&2
  exit 1
fi

node_version="$($NODE_BIN --version)"
[[ "$node_version" == v* ]] || {
  echo "Bundled Node did not return a version: $NODE_BIN" >&2
  exit 1
}
printf 'SIMICHAT_DESKTOP_BUNDLE_BINARY_READY %s %s\n' "$TARGET" "$NODE_BIN"

SIMICHAT_BUNDLED_NODE_PATH="$NODE_BIN" \
SIMICHAT_MCP_RUNTIME_PORT="${SIMICHAT_MCP_RUNTIME_PORT:-37668}" \
  "$ROOT_DIR/scripts/smoke_bundled_node_runtime.sh"

printf 'SIMICHAT_DESKTOP_BUNDLE_RUNTIME_READY %s %s\n' "$TARGET" "$node_version"
