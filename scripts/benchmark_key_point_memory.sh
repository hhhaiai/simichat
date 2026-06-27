#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter test test/benchmark/key_point_memory_benchmark.dart "$@"
