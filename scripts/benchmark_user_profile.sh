#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter test test/benchmark/user_profile_benchmark.dart "$@"
