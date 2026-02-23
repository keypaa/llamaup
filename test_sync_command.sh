#!/bin/bash
# Test script for llama-models sync command (Task 18)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${HOME}/.local/share/llama-models-test"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${CYAN}TEST ${TESTS_RUN}: ${test_name}${RESET}"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ PASS${RESET}\n"
}

fail() {
  local msg="$1"
  echo -e "${RED}✗ FAIL: ${msg}${RESET}\n"
}

cleanup() {
  echo -e "${YELLOW}Cleaning up test directory...${RESET}"
  rm -rf "$MODELS_DIR"
}

# Cleanup on exit
trap cleanup EXIT

# Clean start
rm -rf "$MODELS_DIR"
mkdir -p "$MODELS_DIR"

export LLAMA_MODELS_DIR="$MODELS_DIR"

#
# TEST 1: Sync with no local models
#
run_test "Sync with no local models"
output=$("${SCRIPT_DIR}/scripts/llama-models" sync 2>&1 || true)
if echo "$output" | grep -q "No models downloaded yet"; then
  pass
else
  fail "Expected 'No models downloaded yet' message"
fi

#
# TEST 2: Create mock model
#
run_test "Create mock model with metadata"
model_dir="${MODELS_DIR}/test/model-GGUF"
mkdir -p "$model_dir"

cat > "${model_dir}/metadata.json" << 'EOF'
{
  "model_id": "test/model-GGUF",
  "storage_path": "",
  "downloads": [
    {
      "filename": "model-Q4_K_M.gguf",
      "quantization": "Q4_K_M",
      "quality_label": "⭐ Recommended",
      "file_size": 1000000,
      "file_size_human": "1 MB",
      "downloaded_at": "2025-01-15T10:30:00Z"
    }
  ]
}
EOF

if [[ -f "${model_dir}/metadata.json" ]]; then
  pass
else
  fail "Failed to create metadata.json"
fi

#
# TEST 3: Sync detects local model
#
run_test "Sync detects local model"
output=$("${SCRIPT_DIR}/scripts/llama-models" sync 2>&1 || true)
if echo "$output" | grep -q "test/model-GGUF"; then
  pass
else
  fail "Expected model name in sync output"
fi

#
# TEST 4: Sync runs without fatal errors
#
run_test "Sync runs and shows output"
output=$("${SCRIPT_DIR}/scripts/llama-models" sync 2>&1 || true)
# Should at least show the "Checking for Updates" message
if echo "$output" | grep -q "Checking for Updates"; then
  pass
else
  fail "Sync did not run properly"
fi

#
# Summary
#
echo "=================================="
echo -e "${CYAN}Test Summary${RESET}"
echo "=================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${RESET}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${RESET}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
  echo -e "\n${GREEN}All tests passed! ✓${RESET}"
  exit 0
else
  echo -e "\n${RED}Some tests failed${RESET}"
  exit 1
fi
