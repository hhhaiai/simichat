#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_ID="${1:-${DEVICE_ID:-37101FDJH0077P}}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
TEST_TARGETS=(
  "integration_test/mobile_mcp_app_native_real_smoke_test.dart"
  "integration_test/mobile_extensions_real_smoke_test.dart"
  "integration_test/mobile_mcp_skills_memory_local_real_smoke_test.dart"
  "integration_test/mobile_mcp_skills_memory_smoke_test.dart"
  "integration_test/mobile_node_mcp_real_smoke_test.dart"
)

for test_target in "${TEST_TARGETS[@]}"; do
  if [[ ! -f "$test_target" ]]; then
    echo "Missing integration test: $test_target" >&2
    exit 1
  fi

  "$FLUTTER_BIN" --no-version-check test "$test_target" \
    -d "$DEVICE_ID" --no-pub -r expanded
done

echo "SIMICHAT_MCP_SKILLS_MEMORY_LOCAL_SUITE_READY"
