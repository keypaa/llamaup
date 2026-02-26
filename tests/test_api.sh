#!/usr/bin/env bash
# Quick test script for Phase 2 API functions

set -euo pipefail

# Source color helpers and API functions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

HF_API_URL="https://huggingface.co/api/models"

info() { echo -e "${CYAN}→${RESET} $*" >&2; }
success() { echo -e "${GREEN}✓${RESET} $*" >&2; }

# Copy the search_models function
search_models() {
  local query="${1:-}"
  local limit="${2:-5}"
  local api_url="${HF_API_URL}"
  
  # CRITICAL: full=true returns siblings array with file metadata
  local params="limit=${limit}&sort=downloads&direction=-1&full=true"
  
  if [[ -n "$query" ]]; then
    local encoded_query
    encoded_query=$(echo "$query" | sed 's/ /%20/g')
    params="${params}&search=${encoded_query}"
  fi
  
  params="${params}&filter=gguf"
  
  info "Searching HuggingFace for GGUF models..."
  [[ -n "$query" ]] && info "Query: ${BOLD}${query}${RESET}"
  
  local response
  if ! response=$(curl -fsSL --max-time 30 "${api_url}?${params}"); then
    echo "ERROR: Failed to query API" >&2
    return 1
  fi
  
  if ! echo "$response" | jq empty 2>/dev/null; then
    echo "ERROR: Invalid JSON" >&2
    return 1
  fi
  
  echo "$response"
}

# Run the test
echo
info "Phase 2 API Test"
echo

# Test 1: Search for "llama" models
results=$(search_models "llama" 3)
success "API call successful"

# Defensive check: verify results is valid JSON
if [[ -z "$results" ]] || ! echo "$results" | jq empty 2>/dev/null; then
  echo "ERROR: results is empty or invalid JSON" >&2
  exit 1
fi

# Count models
count=$(echo "$results" | jq 'length')
echo
echo -e "${BOLD}Top ${count} llama GGUF models:${RESET}"
echo

# Use process substitution instead of pipe to avoid subshell issues
while read -r model; do
  # Extract metadata directly with jq
  id=$(echo "$model" | jq -r '.id')
  downloads=$(echo "$model" | jq -r '.downloads // 0')
  
  # Count GGUF files
  n_gguf=$(echo "$model" | jq -r '[.siblings // [] | .[] | select(.rfilename | endswith(".gguf"))] | length')
  
  # Calculate total size
  total_size=$(echo "$model" | jq -r '[.siblings // [] | .[] | select(.rfilename | endswith(".gguf")) | .size // 0] | add // 0')
  
  # Format size
  if command -v numfmt >/dev/null 2>&1; then
    size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
  else
    size_human=$(awk "BEGIN {printf \"%.1fGiB\", $total_size/1024/1024/1024}")
  fi
  
  # Format downloads
  if command -v numfmt >/dev/null 2>&1; then
    downloads_human=$(numfmt --grouping "$downloads" 2>/dev/null || echo "$downloads")
  else
    downloads_human="$downloads"
  fi
  
  echo -e "  ${BOLD}${id}${RESET}"
  echo "    Downloads:  ${downloads_human}"
  echo "    GGUF Size:  ${size_human}"
  echo "    Quants:     ${n_gguf} variants"
  echo
done < <(echo "$results" | jq -c '.[]')

success "Phase 2 complete!"

