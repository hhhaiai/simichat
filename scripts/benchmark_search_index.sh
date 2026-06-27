#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter test test/benchmark/search_index_benchmark.dart "$@"
