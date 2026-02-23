#!/usr/bin/env bash
# Test script for minimal search functionality
set -euo pipefail

cd "$(dirname "$0")"

echo "=== Testing minimal search flow ==="
echo

# Source the llama-models script
source scripts/llama-models

# Test 1: API call returns valid JSON
echo "Test 1: API call returns valid JSON"
results=$(search_models "tiny" 5)
count=$(echo "$results" | jq '. | length')
echo "✓ Got $count models"
echo

# Test 2: parse_model_metadata works
echo "Test 2: parse_model_metadata extracts data"
first_model=$(echo "$results" | jq -c '.[0]')
metadata=$(parse_model_metadata "$first_model")
echo "✓ Metadata: $metadata"
echo

# Test 3: list_gguf_files works
echo "Test 3: list_gguf_files extracts GGUF files"
gguf_files=$(list_gguf_files "$first_model")
gguf_count=$(echo "$gguf_files" | jq '. | length')
echo "✓ Found $gguf_count GGUF files"
echo

# Test 4: Arrays can be populated
echo "Test 4: Array population"
declare -a model_ids
declare -a model_metadata  
declare -a model_jsons

index=0
while IFS= read -r model; do
  local_metadata=$(parse_model_metadata "$model")
  model_id=$(echo "$local_metadata" | cut -d'|' -f1)
  
  model_ids[index]="$model_id"
  model_metadata[index]="$local_metadata"
  model_jsons[index]="$model"
  
  ((index++))
done < <(echo "$results" | jq -c '.[]')

echo "✓ Populated ${#model_ids[@]} models into arrays"
echo

# Test 5: Display logic
echo "Test 5: Display table"
for i in "${!model_ids[@]}"; do
  metadata="${model_metadata[i]}"
  IFS='|' read -r model_id downloads size quant_count <<< "$metadata"
  printf "  %d. %s (%s variants)\n" "$((i+1))" "$model_id" "$quant_count"
done
echo

echo "=== All tests passed! ==="
