#!/usr/bin/env bash
set -euo pipefail

# Prepare the exact Node binary that the desktop Flutter bundle will carry.
# Runtime never downloads or resolves node from PATH. This script is a build
# prerequisite, not an application fallback.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/tools/node_runtime/manifest.json"
OUT_DIR="$ROOT_DIR/tools/node_runtime/bundled"
VERSION="$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    print(json.load(handle)['nodeVersion'])
PY
)"
BASE_URL="$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    print(json.load(handle)['source'].rstrip('/'))
PY
)"

platform_id="${SIMICHAT_NODE_RUNTIME_PLATFORM:-}"
if [[ -z "$platform_id" ]]; then
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) platform_id="macos-arm64" ;;
    Darwin:x86_64) platform_id="macos-x64" ;;
    Linux:aarch64|Linux:arm64) platform_id="linux-arm64" ;;
    Linux:x86_64|Linux:amd64) platform_id="linux-x64" ;;
    MINGW*:AMD64|MSYS*:AMD64) platform_id="windows-x64" ;;
    MINGW*:ARM64|MSYS*:ARM64) platform_id="windows-arm64" ;;
    *) echo "Unsupported host platform: $(uname -s) $(uname -m)" >&2; exit 2 ;;
  esac
fi

case "$platform_id" in
  macos-arm64|macos-x64|linux-arm64|linux-x64) executable="node";;
  windows-arm64|windows-x64) executable="node.exe";;
  *) echo "Unsupported SIMICHAT_NODE_RUNTIME_PLATFORM: $platform_id" >&2; exit 2 ;;
esac

archive="$(python3 - "$MANIFEST" "$platform_id" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding='utf-8'))
print(manifest['platforms'][sys.argv[2]]['archive'])
PY
)"

expected_sha="$(python3 - "$MANIFEST" "$platform_id" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
print(manifest['platforms'][sys.argv[2]]['sha256'])
PY
)"

cache_dir="${SIMICHAT_NODE_RUNTIME_CACHE:-$ROOT_DIR/.cache/node-runtime}"
mkdir -p "$cache_dir" "$OUT_DIR/$platform_id"
archive_path="$cache_dir/$archive"
if [[ ! -f "$archive_path" ]]; then
  archive_part="$archive_path.part"
  curl --fail --location --retry 3 --retry-delay 2 \
    --output "$archive_part" "$BASE_URL/$archive"
  mv "$archive_part" "$archive_path"
fi

actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "SHA-256 mismatch for $archive: expected $expected_sha, got $actual_sha" >&2
  exit 1
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/simichat-node-runtime.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
case "$archive" in
  *.tar.gz) tar -xzf "$archive_path" -C "$staging" ;;
  *.zip) unzip -q "$archive_path" -d "$staging" ;;
esac
source_node="$(find "$staging" -type f -name "$executable" -print -quit)"
if [[ -z "$source_node" ]]; then
  echo "Node executable was not found in $archive" >&2
  exit 1
fi
target="$OUT_DIR/$platform_id/$executable"
target_part="$target.part"
cp "$source_node" "$target_part"
chmod 700 "$target_part" || true
mv -f "$target_part" "$target"
printf 'SIMICHAT_BUNDLED_NODE_READY %s %s\n' "$platform_id" "$OUT_DIR/$platform_id/$executable"
