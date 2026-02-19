#!/usr/bin/env bash
# detect.sh — Report local GPU / SM / CUDA environment info.
# Can be executed directly (produces a report) or sourced by other scripts
# to import lookup_sm(), detect_cuda_version(), and detect_driver_version().
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colour constants
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# usage — print CLI help and exit 0
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: detect.sh [OPTIONS]

Report the local GPU model(s), SM version, CUDA toolkit version, and driver
version. Useful for diagnosing which pre-built binary to use with pull.sh.

Options:
  --json          Output as JSON instead of human-readable text
  --gpu-map PATH  Path to gpu_map.json
                  (default: ${SCRIPT_DIR}/../configs/gpu_map.json)
  -h, --help      Show this help

Examples:
  ./scripts/detect.sh
  ./scripts/detect.sh --json
  ./scripts/detect.sh --gpu-map /path/to/gpu_map.json
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# error — print a red error message to stderr and exit 1
# Args: $1 = message
# ---------------------------------------------------------------------------
error() {
  echo -e "${RED}Error: $1${RESET}" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# warn — print a yellow warning to stderr (does NOT exit)
# Args: $1 = message
# ---------------------------------------------------------------------------
warn() {
  echo -e "${YELLOW}Warning: $1${RESET}" >&2
}

# ---------------------------------------------------------------------------
# check_deps — verify nvidia-smi and jq are available
# Exits 1 with a clear message listing what's missing.
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()

  command -v nvidia-smi >/dev/null 2>&1 || missing+=("nvidia-smi")
  command -v jq         >/dev/null 2>&1 || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Error: missing required tools: ${missing[*]}${RESET}" >&2
    echo "  → Install nvidia-smi by installing the NVIDIA driver." >&2
    echo "  → Install jq: https://jqlang.org/download/" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# get_gpu_names — query nvidia-smi for all connected GPU names
# Returns: newline-separated GPU names (one per GPU) on stdout
# Exits 1 if nvidia-smi is not found or returns no output.
# ---------------------------------------------------------------------------
get_gpu_names() {
  local names
  names=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null) || {
    error "nvidia-smi failed. Check that the NVIDIA driver is installed and a GPU is present."
  }

  if [[ -z "$names" ]]; then
    error "No GPUs detected. Run 'nvidia-smi' manually to check your setup."
  fi

  echo "$names"
}

# ---------------------------------------------------------------------------
# lookup_sm — look up the SM version for a GPU name in gpu_map.json
# Uses case-insensitive substring matching: checks if any GPU string in the
# map is contained within the given GPU name (or vice versa).
# Args:
#   $1 = gpu_name  (e.g. "NVIDIA GeForce RTX 4090")
#   $2 = gpu_map   (path to gpu_map.json)
# Returns: SM version string (e.g. "89") on stdout, or empty string if not found
# Does NOT exit on no match — caller decides what to do.
# ---------------------------------------------------------------------------
lookup_sm() {
  local gpu_name="$1"
  local gpu_map="$2"
  local gpu_name_lower
  gpu_name_lower=$(echo "$gpu_name" | tr '[:upper:]' '[:lower:]')

  # For each GPU entry in the map, check if that entry's name is a substring
  # of the detected GPU name (case-insensitive). We use jq to flatten all
  # entries into "sm|gpu_substring" lines, then grep for a match in bash.
  local sm=""
  while IFS='|' read -r candidate_sm candidate_gpu; do
    local candidate_lower
    candidate_lower=$(echo "$candidate_gpu" | tr '[:upper:]' '[:lower:]')
    # Check if the map entry is a substring of the detected GPU name
    if [[ "$gpu_name_lower" == *"$candidate_lower"* ]]; then
      sm="$candidate_sm"
      break
    fi
  done < <(jq -r '
    .gpu_families | to_entries[] |
    .value.sm as $sm |
    .value.gpus[] |
    "\($sm)|\(.)"
  ' "$gpu_map")

  echo "$sm"
}

# ---------------------------------------------------------------------------
# lookup_family — get a specific field for an SM version from gpu_map.json
# Args:
#   $1 = sm_version  (e.g. "89")
#   $2 = field       (e.g. "architecture" or "cuda_min")
#   $3 = gpu_map     (path to gpu_map.json)
# Returns: field value on stdout, or empty string if not found
# ---------------------------------------------------------------------------
lookup_family() {
  local sm_version="$1"
  local field="$2"
  local gpu_map="$3"

  jq -r \
    --arg sm "$sm_version" \
    --arg field "$field" \
    '.gpu_families | to_entries[] | select(.value.sm == $sm) | .value[$field]' \
    "$gpu_map"
}

# ---------------------------------------------------------------------------
# detect_cuda_version — detect the CUDA toolkit version via nvcc
# Returns: version string like "12.4" on stdout, or empty string if not found
# ---------------------------------------------------------------------------
detect_cuda_version() {
  if ! command -v nvcc >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  local raw
  raw=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+\.[0-9]+' || true)
  echo "$raw"
}

# ---------------------------------------------------------------------------
# detect_driver_version — detect the NVIDIA driver version via nvidia-smi
# Returns: version string like "535.104.05" on stdout, or empty string on failure
# ---------------------------------------------------------------------------
detect_driver_version() {
  local raw
  raw=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
        | head -n1 \
        || true)
  echo "$raw"
}

# ---------------------------------------------------------------------------
# main — entrypoint when detect.sh is executed directly (not sourced)
# ---------------------------------------------------------------------------
main() {
  local output_json=false
  local gpu_map="${SCRIPT_DIR}/../configs/gpu_map.json"

  # --- parse arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)      output_json=true ; shift ;;
      --gpu-map)   gpu_map="$2"     ; shift 2 ;;
      -h|--help)   usage ;;
      *)           error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done

  # --- validate gpu_map path ---
  if [[ ! -f "$gpu_map" ]]; then
    error "gpu_map.json not found at: $gpu_map\n  → Use --gpu-map to specify its location."
  fi

  check_deps

  # --- collect GPU info ---
  local gpu_names_raw
  gpu_names_raw=$(get_gpu_names)

  local cuda_version
  cuda_version=$(detect_cuda_version)

  local driver_version
  driver_version=$(detect_driver_version)

  # --- build result arrays ---
  local -a gpu_names_arr=()
  local -a sm_arr=()
  local -a arch_arr=()
  local -a cuda_min_arr=()
  local all_known=true

  while IFS= read -r gpu_name; do
    [[ -z "$gpu_name" ]] && continue
    gpu_names_arr+=("$gpu_name")

    local sm arch cuda_min
    sm=$(lookup_sm "$gpu_name" "$gpu_map")

    if [[ -n "$sm" ]]; then
      arch=$(lookup_family "$sm" "architecture" "$gpu_map")
      cuda_min=$(lookup_family "$sm" "cuda_min" "$gpu_map")
    else
      arch="unknown"
      cuda_min="unknown"
      all_known=false
    fi

    sm_arr+=("$sm")
    arch_arr+=("$arch")
    cuda_min_arr+=("$cuda_min")
  done <<< "$gpu_names_raw"

  # --- output ---
  if [[ "$output_json" == "true" ]]; then
    # Build JSON output using jq
    local json_gpus="[]"
    for i in "${!gpu_names_arr[@]}"; do
      json_gpus=$(jq -n \
        --argjson arr "$json_gpus" \
        --arg name "${gpu_names_arr[$i]}" \
        --arg sm "${sm_arr[$i]}" \
        --arg arch "${arch_arr[$i]}" \
        --arg cuda_min "${cuda_min_arr[$i]}" \
        '$arr + [{"name":$name,"sm":$sm,"architecture":$arch,"cuda_min":$cuda_min}]')
    done

    jq -n \
      --argjson gpus "$json_gpus" \
      --arg cuda_toolkit "${cuda_version:-not found}" \
      --arg driver "${driver_version:-not found}" \
      '{"gpus":$gpus,"cuda_toolkit":$cuda_toolkit,"driver":$driver}'
  else
    echo -e "\n${BOLD}[llamaup detect]${RESET}\n"

    for i in "${!gpu_names_arr[@]}"; do
      echo -e "  ${CYAN}GPU ${i}:${RESET}  ${gpu_names_arr[$i]}"
      if [[ -n "${sm_arr[$i]}" ]]; then
        echo -e "    SM version : ${GREEN}${sm_arr[$i]}${RESET}  (${arch_arr[$i]})"
        echo -e "    CUDA min   : ${cuda_min_arr[$i]}"
      else
        echo -e "    SM version : ${YELLOW}unknown${RESET}"
        echo -e "    ${YELLOW}→ GPU not found in gpu_map.json. Please open an issue:${RESET}"
        echo -e "    ${YELLOW}  https://github.com/keypaa/llamaup/issues/new?template=wrong_sm.md${RESET}"
      fi
      echo
    done

    local cuda_display="${cuda_version:-not found}"
    local driver_display="${driver_version:-not found}"

    echo -e "  CUDA toolkit : ${cuda_display}$([ -n "${cuda_version}" ] && echo "  (nvcc)")"
    echo -e "  Driver       : ${driver_display}"
    echo

    if [[ "$all_known" == "true" ]]; then
      echo -e "  ${GREEN}All GPUs have known SM versions. ✓${RESET}"
    else
      echo -e "  ${YELLOW}Some GPUs could not be matched to an SM version.${RESET}"
      echo -e "  ${YELLOW}Run with --json and paste the output in a GitHub issue.${RESET}"
    fi
    echo
  fi
}

# ---------------------------------------------------------------------------
# Only run main() if this script is being executed, not sourced.
# ${BASH_SOURCE[0]} is the path of this file.
# $0 is the path of the currently executing script.
# If they're the same, we're being run directly.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
