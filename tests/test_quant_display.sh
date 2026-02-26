#!/usr/bin/env bash
# Test quantization display with labels

set -euo pipefail

# Navigate to script directory
cd "$(dirname "$0")"

# Source the main script to get functions
source scripts/llama-models

echo "Testing quantization display with quality labels"
echo "================================================="
echo

# Fetch a model with multiple quantizations
model_id="bartowski/Llama-3.2-1B-Instruct-GGUF"

info "Fetching model: $model_id"
model_json=$(curl -fsSL "${HF_API_URL}/${model_id}?full=true" 2>/dev/null)

if [[ -z "$model_json" ]]; then
  error "Failed to fetch model"
fi

success "Model fetched successfully"
echo

# Get GGUF files
gguf_files=$(list_gguf_files "$model_json")

# Parse into arrays (same logic as show_model_quantizations)
filenames=()
sizes=()
quants=()

mapfile -t gguf_array < <(echo "$gguf_files" | jq -c '.[]')

for i in "${!gguf_array[@]}"; do
  filename=$(echo "${gguf_array[i]}" | jq -r '.filename')
  size=$(echo "${gguf_array[i]}" | jq -r '.size')
  quant=$(echo "${gguf_array[i]}" | jq -r '.quant')
  
  filenames[i]="$filename"
  sizes[i]="$size"
  quants[i]="$quant"
done

# Display table with labels
echo -e "${BOLD}Available quantizations (first 10):${RESET}"
echo
echo -e "${BOLD}#   Quant     Size        Quality     Filename${RESET}"
echo "─────────────────────────────────────────────────────────────────────────────"

# Show first 10 quantizations
for i in $(seq 0 9); do
  if [[ $i -ge ${#filenames[@]} ]]; then
    break
  fi
  
  size_human=$(format_size "${sizes[i]}")
  
  # Get quality label
  label_info=$(get_quant_label "${quants[i]}")
  IFS='|' read -r label_text label_color <<< "$label_info"
  
  # Truncate filename if too long
  display_name="${filenames[i]}"
  if [[ ${#display_name} -gt 35 ]]; then
    display_name="${display_name:0:32}..."
  fi
  
  printf "${CYAN}%-3d${RESET} %-9s %-11s ${label_color}%-10s${RESET} %s\n" \
    "$((i+1))" "${quants[i]}" "$size_human" "$label_text" "$display_name"
done

echo
success "Quantization labels displayed successfully! ✨"
