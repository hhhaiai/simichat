#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test test/benchmark/obsidian_vault_export_benchmark.dart --dart-define=SIMICHAT_OBSIDIAN_BENCH_FILES="${SIMICHAT_OBSIDIAN_BENCH_FILES:-200}"
