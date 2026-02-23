#!/usr/bin/env bash
# Test just the display portion of minimal search
set -euo pipefail

cd "$(dirname "$0")"

source scripts/llama-models 2>/dev/null || true

# Get test data
echo "Fetching test data..."
results=$(search_models "tiny" 5 2>/dev/null)

# Parse into arrays (same as run_minimal_search)
declare -a model_ids
declare -a model_metadata_arr
declare -a model_jsons

index=0
while IFS= read -r model; do
  metadata=$(parse_model_metadata "$model")
  model_id=$(echo "$metadata" | cut -d'|' -f1)
  
  model_ids[index]="$model_id"
  model_metadata_arr[index]="$metadata"  
  model_jsons[index]="$model"
  
  ((index++))
done < <(echo "$results" | jq -c '.[]')

# Display (same as run_minimal_search)
echo
echo "Found ${#model_ids[@]} GGUF models:"
echo
echo "#   Model ID                                Downloads   Variants"
echo "─────────────────────────────────────────────────────────────────────────────"

for i in "${!model_ids[@]}"; do
  metadata="${model_metadata_arr[i]}"
  IFS='|' read -r model_id downloads size quant_count <<< "$metadata"
  
  display_id="$model_id"
  if [[ ${#model_id} -gt 38 ]]; then
    display_id="${model_id:0:35}..."
  fi
  
  printf "%-3d %-38s %10s   %8s\n" \
    "$((i+1))" "$display_id" "$downloads" "$quant_count"
done

echo
echo "✓ Display test passed!"
