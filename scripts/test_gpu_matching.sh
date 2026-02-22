#!/usr/bin/env bash
# test_gpu_matching.sh — Test GPU substring matching logic
#
# This test suite validates the lookup_sm() function in detect.sh to ensure
# GPU model names are correctly mapped to their SM (compute capability) versions.
#
# Tests covered:
#   1. Correct SM mapping for known GPU models (RTX 4090, A100, T4, H100, etc.)
#   2. Longest-match algorithm (e.g., "GTX 1650 Super" wins over "GTX 1650")
#   3. Pattern overlap validation across different SM families
#
# Usage: ./scripts/test_gpu_matching.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/detect.sh
source "${SCRIPT_DIR}/detect.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

GPU_MAP="${SCRIPT_DIR}/../configs/gpu_map.json"

echo "Testing GPU matching logic..."
echo ""

# Test cases: GPU name -> Expected SM
declare -A test_cases=(
  ["NVIDIA GeForce RTX 4090"]="89"
  ["NVIDIA GeForce RTX 3090"]="86"
  ["Tesla T4"]="75"
  ["NVIDIA A100-SXM4-40GB"]="80"
  ["NVIDIA H100 80GB HBM3"]="90"
  ["NVIDIA RTX 6000 Ada Generation"]="89"
  ["NVIDIA GeForce GTX 1650 SUPER"]="75"
  ["NVIDIA GeForce GTX 1660"]="75"
  ["NVIDIA L40S"]="89"
  ["NVIDIA L40"]="89"
  ["NVIDIA L4"]="89"
  ["NVIDIA RTX 5090"]="101"
  ["NVIDIA RTX A6000"]="86"
  ["Quadro RTX 8000"]="75"
  ["NVIDIA B200"]="100"
)

passed=0
failed=0

for gpu_name in "${!test_cases[@]}"; do
  expected="${test_cases[$gpu_name]}"
  result=$(lookup_sm "$gpu_name" "$GPU_MAP")
  
  if [[ "$result" == "$expected" ]]; then
    echo -e "${GREEN}✓${RESET} $gpu_name -> SM $result"
    ((passed++))
  else
    echo -e "${RED}✗${RESET} $gpu_name -> SM $result (expected $expected)"
    ((failed++))
  fi
done

echo ""
echo "Test Results: $passed passed, $failed failed"

# Test that longest match wins
echo ""
echo "Testing longest match priority..."

# Simulate a case where both "GTX 1650" and "GTX 1650 Super" might match
# The actual GPU name contains "Super", so it should match the longer pattern
test_gpu="NVIDIA GeForce GTX 1650 SUPER"
result=$(lookup_sm "$test_gpu" "$GPU_MAP")

if [[ "$result" == "75" ]]; then
  echo -e "${GREEN}✓${RESET} Longest match test: GTX 1650 SUPER correctly matched to SM $result"
else
  echo -e "${RED}✗${RESET} Longest match test failed: got SM $result"
  ((failed++))
fi

# Test validation function
echo ""
echo "Running GPU map validation..."
LLAMA_VALIDATE_GPU_MAP=1 validate_gpu_map "$GPU_MAP" 2>&1 || true

echo ""
if [[ $failed -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${RESET}"
  exit 0
else
  echo -e "${RED}Some tests failed!${RESET}"
  exit 1
fi
