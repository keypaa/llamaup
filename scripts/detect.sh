#!/usr/bin/env bash
# detect.sh — Report local GPU / SM / CUDA environment info.
# Can be executed directly (produces a report) or sourced by other scripts
# to import lookup_sm(), detect_cuda_version(), and detect_driver_version().
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colour constants (only if stdout is a TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  RESET=''
fi

INSTALL_DEPS=false

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
  --install-deps   Attempt to install missing tools (jq) automatically
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
    if [[ "$INSTALL_DEPS" == "true" ]]; then
      install_deps "${missing[@]}"
      # Recompute missing after attempt
      missing=()
      command -v nvidia-smi >/dev/null 2>&1 || missing+=("nvidia-smi")
      command -v jq         >/dev/null 2>&1 || missing+=("jq")
      if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: still missing required tools after install attempt: ${missing[*]}${RESET}" >&2
        echo "  → Install nvidia-smi by installing the NVIDIA driver." >&2
        echo "  → Install jq: https://jqlang.org/download/" >&2
        exit 1
      fi
    else
      echo -e "${RED}Error: missing required tools: ${missing[*]}${RESET}" >&2
      echo "  → Install nvidia-smi by installing the NVIDIA driver." >&2
      echo "  → Install jq: https://jqlang.org/download/" >&2
      exit 1
    fi
  fi
}


# ---------------------------------------------------------------------------
# install_deps — attempt to install missing tools (best-effort)
# Args: list of missing tools (e.g. jq nvidia-smi)
# ---------------------------------------------------------------------------
install_deps() {
  local pkgs=("$@")

  for pkg in "${pkgs[@]}"; do
    case "$pkg" in
      jq)
        echo "Installing jq..."
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update && sudo apt-get install -y jq && continue
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y jq && continue
        elif command -v pacman >/dev/null 2>&1; then
          sudo pacman -Syu --noconfirm jq && continue
        elif command -v apk >/dev/null 2>&1; then
          sudo apk add jq && continue
        elif command -v brew >/dev/null 2>&1; then
          brew install jq && continue
        elif command -v choco >/dev/null 2>&1; then
          choco install jq -y && continue
        else
          echo "No supported package manager found — installing jq binary to /usr/local/bin"
          sudo curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 || true
          sudo chmod +x /usr/local/bin/jq || true
          continue
        fi
        ;;
      nvidia-smi)
        echo "nvidia-smi depends on the NVIDIA driver and cannot be installed automatically."
        echo "Please install the appropriate NVIDIA driver for your OS or follow your cloud provider's guide."
        echo "Ubuntu example: sudo apt-get install -y ubuntu-drivers-common && sudo ubuntu-drivers autoinstall (reboot may be required)"
        ;;
      *)
        echo "Don't know how to install '$pkg' automatically. Please install it manually."
        ;;
    esac
  done
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
# validate_gpu_map — Check for overlapping/ambiguous GPU patterns in gpu_map.json
# Args:
#   $1 = gpu_map (path to gpu_map.json)
# Returns: 0 if valid, prints warnings to stderr for overlaps (does not exit)
# ---------------------------------------------------------------------------
validate_gpu_map() {
  local gpu_map="$1"
  local has_warnings=0

  # Extract all GPU patterns with their SM versions
  local -a patterns=()
  local -a sms=()
  
  while IFS='|' read -r sm gpu; do
    patterns+=("$gpu")
    sms+=("$sm")
  done < <(jq -r '
    .gpu_families | to_entries[] |
    .value.sm as $sm |
    .value.gpus[] |
    "\($sm)|\(.)"
  ' "$gpu_map")

  # Check for substring overlaps between different SM families
  local i j
  for ((i=0; i<${#patterns[@]}; i++)); do
    local pattern_i="${patterns[$i]}"
    local sm_i="${sms[$i]}"
    local pattern_i_lower
    pattern_i_lower=$(echo "$pattern_i" | tr '[:upper:]' '[:lower:]')
    
    for ((j=i+1; j<${#patterns[@]}; j++)); do
      local pattern_j="${patterns[$j]}"
      local sm_j="${sms[$j]}"
      local pattern_j_lower
      pattern_j_lower=$(echo "$pattern_j" | tr '[:upper:]' '[:lower:]')
      
      # Check if one is a substring of the other
      if [[ "$pattern_i_lower" == *"$pattern_j_lower"* && "$sm_i" != "$sm_j" ]]; then
        echo -e "${YELLOW}[WARNING]${RESET} GPU pattern overlap detected:" >&2
        echo -e "  '${BOLD}$pattern_j${RESET}' (SM $sm_j) is a substring of '${BOLD}$pattern_i${RESET}' (SM $sm_i)" >&2
        echo -e "  This may cause ambiguous matches. Consider using more specific patterns." >&2
        has_warnings=1
      elif [[ "$pattern_j_lower" == *"$pattern_i_lower"* && "$sm_i" != "$sm_j" ]]; then
        echo -e "${YELLOW}[WARNING]${RESET} GPU pattern overlap detected:" >&2
        echo -e "  '${BOLD}$pattern_i${RESET}' (SM $sm_i) is a substring of '${BOLD}$pattern_j${RESET}' (SM $sm_j)" >&2
        echo -e "  This may cause ambiguous matches. Consider using more specific patterns." >&2
        has_warnings=1
      fi
    done
  done

  return 0
}

# ---------------------------------------------------------------------------
# lookup_sm — look up the SM version for a GPU name in gpu_map.json
# Uses case-insensitive substring matching: checks if any GPU string in the
# map is contained within the given GPU name (or vice versa).
# Uses "longest match" strategy to handle overlapping patterns correctly.
# For example, "GTX 1650 Super" will match before "GTX 1650" if both are in the map.
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

  # Collect all matches, then pick the longest (most specific) one.
  # This ensures that "GTX 1650 Super" matches before "GTX 1650".
  local best_sm=""
  local best_match_length=0
  
  while IFS='|' read -r candidate_sm candidate_gpu; do
    local candidate_lower
    candidate_lower=$(echo "$candidate_gpu" | tr '[:upper:]' '[:lower:]')
    
    # Check if the map entry is a substring of the detected GPU name
    if [[ "$gpu_name_lower" == *"$candidate_lower"* ]]; then
      local match_length=${#candidate_lower}
      # Use the longest matching pattern
      if (( match_length > best_match_length )); then
        best_sm="$candidate_sm"
        best_match_length="$match_length"
      fi
    fi
  done < <(jq -r '
    .gpu_families | to_entries[] |
    .value.sm as $sm |
    .value.gpus[] |
    "\($sm)|\(.)"
  ' "$gpu_map")

  echo "$best_sm"
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
      --install-deps) INSTALL_DEPS=true ; shift ;;
      --gpu-map)   gpu_map="$2"     ; shift 2 ;;
      -h|--help)   usage ;;
      *)           error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done

  # --- validate gpu_map path ---
  if [[ ! -f "$gpu_map" ]]; then
    error "gpu_map.json not found at: $gpu_map\n  → Use --gpu-map to specify its location."
  fi

  # --- validate gpu_map for overlapping patterns (only in debug mode or if env var set) ---
  if [[ "${LLAMA_DEPLOY_DEBUG:-0}" == "1" ]] || [[ "${LLAMA_VALIDATE_GPU_MAP:-0}" == "1" ]]; then
    validate_gpu_map "$gpu_map"
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
