#!/usr/bin/env bash
# Quick test of the new quantization labels

set -euo pipefail

# Source the get_quant_label function
source ./scripts/llama-models

echo "Testing new quantization categorization:"
echo ""

quants=(
    "F32" "F16" "BF16"                          # Lossless
    "Q8_0" "Q6_K" "Q6_K_L"                      # Near-Lossless
    "Q5_K_M" "Q5_K_S" "Q5_1" "Q4_K_M"           # Recommended
    "Q4_K_S" "Q4_1" "Q4_0" "IQ4_XS" "IQ4_NL"    # Fast
    "Q3_K_L" "Q3_K_M" "Q3_K_S" "Q2_K" "Q2_K_L"  # Lossy (K-quants)
    "IQ3_XXS" "IQ3_XS" "IQ2_XXS" "IQ2_XS"       # Lossy (IQ)
    "MXFP4" "IQ1_S"                             # Experimental
    "UNKNOWN"                                   # Other
)

for quant in "${quants[@]}"; do
    result=$(get_quant_label "$quant")
    label="${result%%|*}"
    color="${result##*|}"
    
    printf "%-12s → %b%-20s%b\n" "$quant" "$color" "$label" "${RESET}"
done
