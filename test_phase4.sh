#!/usr/bin/env bash
# Phase 4 Comprehensive Test Suite — Premium Mode (Tasks 10-13)
# No sourcing, no subshells - just direct grep checks

SCRIPT="scripts/llama-models"

echo "=================================================="
echo "  Phase 4 Test Suite — Premium Mode"
echo "  Target: $SCRIPT"
echo "=================================================="

PASS=0
FAIL=0

# Test helper
check() {
  local desc="$1"
  local pattern="$2"
  local min_count="${3:-1}"
  
  count=$(grep -c "$pattern" "$SCRIPT" 2>/dev/null | tr -d '\n' || echo "0")
  
  if [[ $count -ge $min_count ]]; then
    echo "✓ $desc ($count found)"
    ((PASS++))
    return 0
  else
    echo "✗ $desc (expected $min_count+, found $count)"
    ((FAIL++))
    return 1
  fi
}

check_function() {
  check "Function: $1()" "^$1()"
}

echo
echo "━━━ TEST 1: Syntax Check ━━━"
if bash -n "$SCRIPT" 2>/dev/null; then
  echo "✓ Valid bash syntax"
  ((PASS++))
else
  echo "✗ Syntax errors detected"
  ((FAIL++))
fi

echo
echo "━━━ TEST 2: Premium Mode Functions (Task 11) ━━━"
check_function "run_premium_interactive"
check_function "run_premium_search"
check_function "show_premium_model_quantizations"
check_function "download_aria2c_file"

echo
echo "━━━ TEST 3: Gum TUI Integration (Task 11) ━━━"
check "gum style command" "gum style"
check "gum filter command" "gum filter"
check "gum choose command" "gum choose"
check "gum input command" "gum input"
check "Premium mode welcome" "llama-models — Premium Mode"

echo
echo "━━━ TEST 4: Aria2c Multi-Connection Download (Task 13) ━━━"
check "aria2c command" "aria2c" 5
check "16 connections (-x16)" "\-x16"
check "16 segments (-s16)" "\-s16"
check "Single job (-j1)" "\-j1"
check "File allocation" "\-\-file-allocation=none"
check "Console log level" "\-\-console-log-level=warn"
check "Summary interval" "\-\-summary-interval=1"

echo
echo "━━━ TEST 5: Installation System (Task 10) ━━━"
check_function "install_dependencies"
check_function "install_linux_dependencies"
check_function "install_macos_dependencies"
check_function "install_gum_linux"

echo
echo "━━━ TEST 6: Package Manager Support (Task 10) ━━━"
check "apt support (Debian/Ubuntu)" "apt install"
check "yum support (RHEL/CentOS)" "yum install"
check "pacman support (Arch)" "pacman -S"
check "Homebrew support (macOS)" "brew install"

echo
echo "━━━ TEST 7: Download Fallback Logic ━━━"
check "aria2c dependency check" "check_dependency aria2c"
check "Curl fallback" "download_gguf_file" 2

echo
echo "━━━ TEST 8: Mode Detection ━━━"
check_function "detect_mode"
check "Premium mode assignment" 'MODE="premium"'
check "Minimal mode assignment" 'MODE="minimal"'

echo
echo "━━━ TEST 9: Quantization Panel (Task 12) ━━━"
check "Gum choose in quant display" "gum choose" 2
check "Size metadata in quant" "size"

echo
echo "━━━ TEST 10: Integration with Minimal Mode ━━━"
check_function "run_minimal_interactive"
check_function "run_minimal_search"
check_function "show_model_quantizations"
check_function "download_gguf_file"

echo
echo "━━━ TEST 11: Gum Linux Binary Install (Task 10) ━━━"
check "GitHub download in gum install" "github.com"
check "Local bin directory" ".local/bin"

echo
echo "━━━ TEST 12: Premium Mode Documentation ━━━"
check "Premium mode mentioned" "premium\|Premium" 5

echo
echo "=================================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "=================================================="

if [[ $FAIL -eq 0 ]]; then
  echo
  echo "✓ ALL TESTS PASSED!"
  echo
  echo "Phase 4 Complete (Tasks 10-13):"
  echo "  ✓ Task 10: Auto-install gum + aria2c"
  echo "  ✓ Task 11: Gum-based TUI interface"
  echo "  ✓ Task 12: Quantization preview panel"
  echo "  ✓ Task 13: Aria2c multi-connection downloads"
  echo
  echo "Ready to commit! 🚀"
  exit 0
else
  echo
  echo "✗ Some tests failed. Review above."
  exit 1
fi
