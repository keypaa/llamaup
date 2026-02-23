#!/usr/bin/env bash
# Test quantization label classification

set -euo pipefail

# Source the script to get the function
source scripts/llama-models

echo "Testing quantization label classification:"
echo "=========================================="
echo

# Test cases for each category
test_quants=(
  # Best
  "F16" "BF16" "F32" "Q8_0"
  # Balanced
  "Q6_K" "Q5_K_M" "Q5_0" "Q5_1"
  # Fast
  "Q4_K_M" "Q4_0" "Q4_1" "Q4_K_L"
  # Lossy
  "Q3_K_M" "Q2_K" "IQ3_XXS" "IQ2_XXS" "IQ1_S"
  # Unknown
  "Q9_K" "UNKNOWN"
)

for quant in "${test_quants[@]}"; do
  label_info=$(get_quant_label "$quant")
  IFS='|' read -r label_text label_color <<< "$label_info"
  echo -e "  ${quant}: ${label_color}${label_text}${RESET}"
done

echo
echo "✓ All labels classified successfully"
