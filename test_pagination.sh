#!/usr/bin/env bash
# test_pagination.sh — Test pagination in llama-models
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "${GREEN}✓${RESET} $*"; }
fail() { echo -e "${RED}✗${RESET} $*"; }
info() { echo -e "${CYAN}ℹ${RESET} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_MODELS="${SCRIPT_DIR}/scripts/llama-models"

test_count=0
pass_count=0

run_test() {
  local name="$1"
  shift
  ((test_count++))
  
  echo
  info "Test $test_count: $name"
  
  if "$@"; then
    pass "$name"
    ((pass_count++))
    return 0
  else
    fail "$name"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 1: search_models function has offset parameter
# ---------------------------------------------------------------------------
test_search_offset() {
  # Check if search_models function definition includes skip parameter
  if grep -A 2 '^search_models()' "$LLAMA_MODELS" | grep -q 'skip.*:-0'; then
    echo "  - search_models function accepts skip/offset parameter"
    return 0
  else
    echo "  - search_models function does NOT accept skip/offset parameter"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 2: Verify skip parameter is added to API URL in code
# ---------------------------------------------------------------------------
test_skip_in_url() {
  # Check if skip parameter is constructed in the params
  if grep -A 10 'search_models()' "$LLAMA_MODELS" | grep -q 'params=.*skip'; then
    echo "  - skip parameter construction found in search_models"
    return 0
  else
    echo "  - skip parameter construction NOT found"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 3: Verify "Show more" option appears in select menu
# ---------------------------------------------------------------------------
test_show_more_option() {
  # Check if the "Show more" option is defined in the code
  if grep -q '── Show more ──' "$LLAMA_MODELS"; then
    echo "  - 'Show more' option found in script"
    return 0
  else
    echo "  - 'Show more' option NOT found in script"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 4: Verify array accumulation logic exists
# ---------------------------------------------------------------------------
test_array_accumulation() {
  # Check if arrays are being accumulated with +=
  if grep -q 'all_model_ids+=\|all_model_metadata+=\|all_model_jsons+=' "$LLAMA_MODELS"; then
    echo "  - Array accumulation logic found"
    return 0
  else
    echo "  - Array accumulation logic NOT found"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 5: Verify has_more flag logic
# ---------------------------------------------------------------------------
test_has_more_logic() {
  # Check if has_more is set based on result count
  if grep -A 5 'has_more=' "$LLAMA_MODELS" | grep -q 'model_jsons\[@\]}.*-lt.*limit'; then
    echo "  - has_more flag logic found"
    return 0
  else
    echo "  - has_more flag logic NOT found"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
echo -e "${BOLD}Testing llama-models pagination${RESET}"
echo "Target: $LLAMA_MODELS"

# Syntax check first
if ! bash -n "$LLAMA_MODELS" 2>/dev/null; then
  fail "Syntax error in $LLAMA_MODELS"
  exit 1
fi
pass "Syntax check"

# Run tests
run_test "search_models accepts offset parameter" test_search_offset
run_test "skip parameter added to API URL" test_skip_in_url
run_test "'Show more' option in select menu" test_show_more_option
run_test "Array accumulation logic" test_array_accumulation
run_test "has_more flag logic" test_has_more_logic

# Summary
echo
echo "─────────────────────────────────────────────────────────────────────────────"
echo -e "${BOLD}Results: ${pass_count}/${test_count} tests passed${RESET}"

if [[ $pass_count -eq $test_count ]]; then
  echo -e "${GREEN}All tests passed!${RESET}"
  echo
  info "You can test pagination interactively with:"
  echo "  ./scripts/llama-models search llama"
  echo
  info "Look for the '── Show more ──' option after the first 20 results"
  exit 0
else
  echo -e "${RED}Some tests failed${RESET}"
  exit 1
fi
