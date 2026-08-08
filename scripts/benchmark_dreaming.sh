#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

source scripts/lib/release_pubspec_hook.sh

cleanup() {
  simichat_release_pubspec_restore
}
trap cleanup EXIT

simichat_release_pubspec_setup 0

"$FLUTTER_BIN" --no-version-check test --no-pub \
  test/dreaming_benchmark.dart "$@"
