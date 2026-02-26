#!/usr/bin/env bash
# Test Task 7: Minimal mode bash select menu implementation
set -euo pipefail

cd "$(dirname "$0")"

echo "========================================"
echo "Task 7 Test Suite: Minimal Mode"
echo "========================================"
echo

# Source the script to test functions
source scripts/llama-models 2>/dev/null || true

# Test 1: Syntax check
echo "✓ Test 1: Bash syntax validation"
if bash -n scripts/llama-models 2>/dev/null; then
  echo "  ✓ No syntax errors detected"
else
  echo "  ✗ Syntax errors found!"
  exit 1
fi
echo

# Test 2: API call returns valid JSON
echo "✓ Test 2: HuggingFace API search"
results=$(search_models "tinyllama" 3 2>/dev/null)
if [[ -n "$results" ]] && echo "$results" | jq empty 2>/dev/null; then
  count=$(echo "$results" | jq '. | length')
  echo "  ✓ API returned $count models"
else
  echo "  ✗ API call failed or invalid JSON"
  exit 1
fi
echo

# Test 3: parse_model_metadata extracts data correctly
echo "✓ Test 3: Model metadata parsing"
first_model=$(echo "$results" | jq -c '.[0]')
metadata=$(parse_model_metadata "$first_model")
model_id=$(echo "$metadata" | cut -d'|' -f1)
downloads=$(echo "$metadata" | cut -d'|' -f2)
quant_count=$(echo "$metadata" | cut -d'|' -f4)

if [[ -n "$model_id" ]] && [[ -n "$downloads" ]] && [[ -n "$quant_count" ]]; then
  echo "  ✓ Model ID: $model_id"
  echo "  ✓ Downloads: $downloads"
  echo "  ✓ Quant count: $quant_count"
else
  echo "  ✗ Failed to parse metadata"
  exit 1
fi
echo

# Test 4: list_gguf_files extracts GGUF files
echo "✓ Test 4: GGUF file extraction"
gguf_files=$(list_gguf_files "$first_model")
if [[ -n "$gguf_files" ]] && echo "$gguf_files" | jq empty 2>/dev/null; then
  gguf_count=$(echo "$gguf_files" | jq '. | length')
  echo "  ✓ Found $gguf_count GGUF files"
  
  # Show first GGUF as example
  first_gguf=$(echo "$gguf_files" | jq -r '.[0] | "\(.quant) - \(.filename)"')
  echo "  ✓ Example: $first_gguf"
else
  echo "  ✗ Failed to extract GGUF files"
  exit 1
fi
echo

# Test 5: format_size works
echo "✓ Test 5: Size formatting"
size_1gb=$(format_size 1073741824)
size_1mb=$(format_size 1048576)
size_1kb=$(format_size 1024)

echo "  ✓ 1GB = $size_1gb"
echo "  ✓ 1MB = $size_1mb"
echo "  ✓ 1KB = $size_1kb"
echo

# Test 6: Array population (simulating run_minimal_search logic)
echo "✓ Test 6: Array population and display logic"

# Extract models into a simple array first
mapfile -t model_array < <(echo "$results" | jq -c '.[]')

echo "  ✓ Extracted ${#model_array[@]} models from JSON"

# Test display format with first model
first_meta=$(parse_model_metadata "${model_array[0]}")
IFS='|' read -r m_id m_downloads m_size m_quant_count <<< "$first_meta"

echo
echo "  Sample display output:"
echo "  ────────────────────────────────────────────────────────────────"
printf "  %-3s %-40s %10s %8s\n" "#" "Model ID" "Downloads" "Variants"
echo "  ────────────────────────────────────────────────────────────────"

for i in "${!model_array[@]}"; do
  meta=$(parse_model_metadata "${model_array[i]}")
  IFS='|' read -r m_id m_downloads m_size m_quant_count <<< "$meta"
  
  # Truncate if needed
  display_id="$m_id"
  if [[ ${#m_id} -gt 38 ]]; then
    display_id="${m_id:0:35}..."
  fi
  
  printf "  %-3d %-40s %10s %8s\n" "$((i+1))" "$display_id" "$m_downloads" "$m_quant_count"
done

echo

# Test 7: Check download function exists
echo "✓ Test 7: Download function validation"
if declare -f download_gguf_file > /dev/null; then
  echo "  ✓ download_gguf_file() function exists"
  echo "  ✓ (Skipping actual download to avoid network usage)"
else
  echo "  ✗ download_gguf_file() not found"
  exit 1
fi
echo

# Test 8: Check all required functions exist
echo "✓ Test 8: Function completeness check"
required_functions=(
  "run_minimal_search"
  "run_minimal_interactive"
  "show_model_quantizations"
  "download_gguf_file"
  "format_size"
)

all_exist=true
for func in "${required_functions[@]}"; do
  if declare -f "$func" > /dev/null; then
    echo "  ✓ $func()"
  else
    echo "  ✗ $func() MISSING"
    all_exist=false
  fi
done

if [[ "$all_exist" != true ]]; then
  exit 1
fi
echo

echo "========================================"
echo "✓ All automated tests passed!"
echo "========================================"
echo
echo "To test interactively, run:"
echo "  ./scripts/llama-models search tinyllama"
echo
echo "Or for full interactive mode:"
echo "  ./scripts/llama-models"
echo
