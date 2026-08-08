#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test test/data_import_benchmark.dart --dart-define=SIMICHAT_IMPORT_BENCH_FILES="${SIMICHAT_IMPORT_BENCH_FILES:-200}"
