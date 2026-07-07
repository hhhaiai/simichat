#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

source scripts/lib/release_pubspec_hook.sh

for arg in "$@"; do
  if [[ "$arg" == "--no-test-assets" ]]; then
    echo "Refusing --no-test-assets: clean test runs need Flutter test assets such as shaders/ink_sparkle.frag." >&2
    exit 2
  fi
done

cleanup() {
  simichat_release_pubspec_restore
}
trap cleanup EXIT

simichat_release_pubspec_setup 0

if [[ "$#" -eq 0 ]]; then
  "$FLUTTER_BIN" --no-version-check test --no-pub -r expanded
else
  "$FLUTTER_BIN" --no-version-check test --no-pub "$@"
fi
