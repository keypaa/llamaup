#!/usr/bin/env bash
# Test enhanced metadata saving with quality labels

set -euo pipefail

# Source the script to get functions
source ./scripts/llama-models

# Create a test directory
TEST_DIR="/tmp/llamaup-metadata-test-$$"
mkdir -p "$TEST_DIR"

echo "Testing enhanced metadata saving..."
echo ""

# Create a fake GGUF file
FAKE_FILE="${TEST_DIR}/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
dd if=/dev/zero of="$FAKE_FILE" bs=1M count=10 2>/dev/null

echo "Created test file: $FAKE_FILE (10 MB)"
echo ""

# Test 1: Create new metadata
echo "Test 1: Creating new metadata file..."
save_download_metadata \
  "$TEST_DIR" \
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF" \
  "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"

echo ""
echo "Metadata content:"
jq . "${TEST_DIR}/metadata.json"
echo ""

# Test 2: Add another file to existing metadata
echo "Test 2: Adding another file to existing metadata..."
FAKE_FILE2="${TEST_DIR}/qwen2.5-coder-1.5b-instruct-q8_0.gguf"
dd if=/dev/zero of="$FAKE_FILE2" bs=1M count=20 2>/dev/null

save_download_metadata \
  "$TEST_DIR" \
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF" \
  "qwen2.5-coder-1.5b-instruct-q8_0.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q8_0.gguf"

echo ""
echo "Updated metadata content:"
jq . "${TEST_DIR}/metadata.json"
echo ""

# Test 3: Re-download same file (should update, not duplicate)
echo "Test 3: Re-downloading same file (should update timestamp)..."
sleep 1
save_download_metadata \
  "$TEST_DIR" \
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF" \
  "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"

echo ""
echo "Final metadata content (should have 2 downloads, not 3):"
jq . "${TEST_DIR}/metadata.json"
echo ""

# Verify structure
echo "Verification:"
echo "  - Model ID: $(jq -r '.model_id' "${TEST_DIR}/metadata.json")"
echo "  - Storage path: $(jq -r '.storage_path' "${TEST_DIR}/metadata.json")"
echo "  - Number of downloads: $(jq '.downloads | length' "${TEST_DIR}/metadata.json")"
echo "  - Q4_K_M quality label: $(jq -r '.downloads[] | select(.quantization == "Q4_K_M") | .quality_label' "${TEST_DIR}/metadata.json")"
echo "  - Q8_0 quality label: $(jq -r '.downloads[] | select(.quantization == "Q8_0") | .quality_label' "${TEST_DIR}/metadata.json")"
echo ""

# Cleanup
rm -rf "$TEST_DIR"
echo "✓ Test complete, cleaned up temporary files"
