#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test test/local_transfer_benchmark.dart "$@"
