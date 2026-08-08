#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter test test/mobile_main_flow_smoke_test.dart
flutter analyze
