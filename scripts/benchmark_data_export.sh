#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test test/benchmark/data_export_benchmark.dart --dart-define=SIMICHAT_EXPORT_BENCH_FILES="${SIMICHAT_EXPORT_BENCH_FILES:-200}"
