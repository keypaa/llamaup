#!/usr/bin/env bash
# Test duplicate download detection

set -euo pipefail

# Source the script
source ./scripts/llama-models

echo "Testing duplicate download detection..."
echo ""

# Create test directory
TEST_DIR="$MODELS_DIR/test-duplicate-check"
mkdir -p "$TEST_DIR"

# Create a fake GGUF file
TEST_FILE="test-model-q4_k_m.gguf"
dd if=/dev/zero of="${TEST_DIR}/${TEST_FILE}" bs=1M count=5 2>/dev/null

echo "Created test file: ${TEST_DIR}/${TEST_FILE} (5 MB)"
echo ""

# Test 1: check_existing_file should detect the file
echo "Test 1: Checking if file exists detection works..."
echo "────────────────────────────────────────────────────"

# Simulate user saying "no" to re-download
if check_existing_file "$TEST_DIR" "$TEST_FILE" <<< "n"; then
  echo "❌ FAIL: Expected return code 1 (user said no)"
else
  echo "✓ PASS: Correctly returned 1 (skip download)"
fi

echo ""

# Test 2: FORCE_DOWNLOAD should bypass prompt
echo "Test 2: Testing --force flag (FORCE_DOWNLOAD=true)..."
echo "────────────────────────────────────────────────────"

export FORCE_DOWNLOAD=true
if check_existing_file "$TEST_DIR" "$TEST_FILE"; then
  echo "✓ PASS: FORCE_DOWNLOAD bypassed prompt"
else
  echo "❌ FAIL: FORCE_DOWNLOAD should have returned 0"
fi
unset FORCE_DOWNLOAD

echo ""

# Test 3: Non-existent file should return 0
echo "Test 3: Non-existent file should proceed..."
echo "────────────────────────────────────────────────────"

if check_existing_file "$TEST_DIR" "nonexistent-file.gguf"; then
  echo "✓ PASS: Non-existent file returns 0 (proceed)"
else
  echo "❌ FAIL: Non-existent file should return 0"
fi

echo ""

# Cleanup
rm -rf "$TEST_DIR"
echo "✓ Cleaned up test files"
echo ""
echo "All tests complete!"
