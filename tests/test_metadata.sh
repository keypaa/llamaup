#!/usr/bin/env bash
# Test metadata saving and listing functionality

set -euo pipefail

# Navigate to script directory
cd "$(dirname "$0")"

# Source the main script to get functions
source scripts/llama-models

echo "Testing metadata functionality"
echo "=============================="
echo

# Create a test directory
test_dir="/tmp/llamaup_test_metadata"
rm -rf "$test_dir"
mkdir -p "$test_dir/test-model"

# Test 1: Create metadata
echo "Test 1: Creating metadata..."
cd "$test_dir/test-model"

# Create a fake GGUF file
echo "fake gguf data" > "test-model-Q4_K_M.gguf"

# Save metadata
save_download_metadata \
  "$test_dir/test-model" \
  "test-org/test-model" \
  "test-model-Q4_K_M.gguf" \
  "https://huggingface.co/test-org/test-model/resolve/main/test-model-Q4_K_M.gguf"

if [[ -f "$test_dir/test-model/metadata.json" ]]; then
  success "Metadata file created"
  echo
  echo "Metadata contents:"
  jq . "$test_dir/test-model/metadata.json"
  echo
else
  error "Metadata file not created"
fi

# Test 2: Append to metadata
echo "Test 2: Appending another download..."
echo "fake gguf data 2" > "test-model-Q8_0.gguf"

save_download_metadata \
  "$test_dir/test-model" \
  "test-org/test-model" \
  "test-model-Q8_0.gguf" \
  "https://huggingface.co/test-org/test-model/resolve/main/test-model-Q8_0.gguf"

local downloads_count
downloads_count=$(jq '.downloads | length' "$test_dir/test-model/metadata.json")

if [[ "$downloads_count" == "2" ]]; then
  success "Metadata appended correctly (2 downloads tracked)"
  echo
  jq '.downloads' "$test_dir/test-model/metadata.json"
  echo
else
  error "Metadata append failed (expected 2 downloads, got $downloads_count)"
fi

# Test 3: Verify fields
echo "Test 3: Verifying metadata fields..."
local fields_ok=1

# Check required fields exist
for field in model_id storage_path downloads; do
  if jq -e ".$field" "$test_dir/test-model/metadata.json" >/dev/null 2>&1; then
    success "Field '$field' exists"
  else
    warn "Field '$field' missing"
    fields_ok=0
  fi
done

# Check download entry fields
for field in downloaded_at filename source_url file_size quantization; do
  if jq -e ".downloads[0].$field" "$test_dir/test-model/metadata.json" >/dev/null 2>&1; then
    success "Download field '$field' exists"
  else
    warn "Download field '$field' missing"
    fields_ok=0
  fi
done

echo

if [[ $fields_ok -eq 1 ]]; then
  success "All metadata fields present ✓"
else
  warn "Some metadata fields missing"
fi

# Cleanup
echo
info "Cleaning up test directory..."
cd -
rm -rf "$test_dir"

echo
success "Metadata tests complete! ✨"
