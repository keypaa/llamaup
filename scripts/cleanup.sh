#!/usr/bin/env bash
# cleanup.sh — List and remove old installed llama.cpp versions
#
# Helps manage disk space by identifying and removing old llama.cpp installations
# while preserving recent versions. Supports interactive mode (prompts for each),
# automatic mode (keep N most recent), and dry-run mode (preview without deleting).
#
# Usage: ./scripts/cleanup.sh [OPTIONS]
#        See --help for full options
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # SCRIPT_DIR reserved for future use

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

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: cleanup.sh [OPTIONS]

List installed llama.cpp versions and optionally remove old ones.

Options:
  --install-dir <dir>   Installation root directory. Default: ~/.local/bin/llama
  --keep <n>            Keep the N most recent versions, remove the rest. Default: prompt for each
  --all                 Remove all installed versions (prompts for confirmation)
  --dry-run             Show what would be removed without removing it
  -h, --help            Show this help

Examples:
  ./scripts/cleanup.sh                           # Interactive mode
  ./scripts/cleanup.sh --keep 2                  # Keep 2 most recent, remove others
  ./scripts/cleanup.sh --all                     # Remove all versions (with prompt)
  ./scripts/cleanup.sh --dry-run --keep 1        # Show what would be removed
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
error()   { echo -e "${RED}Error: $1${RESET}" >&2; exit 1; }
info()    { echo -e "${CYAN}→ $1${RESET}"; }
success() { echo -e "${GREEN}✓ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}" >&2; }

# ---------------------------------------------------------------------------
# list_installed_versions — find all installed version directories
# Args: $1 = install_dir
# Returns: newline-separated list of versioned directories (full paths)
#          sorted by modification time (newest first)
# ---------------------------------------------------------------------------
list_installed_versions() {
  local install_dir="$1"
  local parent_dir
  parent_dir="$(dirname "$install_dir")"
  
  if [[ ! -d "$parent_dir" ]]; then
    return 0
  fi
  
  # Find all versioned directories matching pattern: llama-{version}-sm{sm}
  # Sort by modification time (newest first)
  find "$parent_dir" -maxdepth 1 -type d -name "llama-*-sm*" -printf "%T@ %p\n" 2>/dev/null \
    | sort -rn \
    | cut -d' ' -f2-
}

# ---------------------------------------------------------------------------
# get_version_info — extract version and SM from directory name
# Args: $1 = directory path
# Returns: "version|sm|size" on stdout, or empty if parsing fails
# ---------------------------------------------------------------------------
get_version_info() {
  local dir="$1"
  local basename
  basename="$(basename "$dir")"
  
  # Parse: llama-{version}-sm{sm}
  if [[ "$basename" =~ ^llama-([^-]+)-sm([0-9]+)$ ]]; then
    local version="${BASH_REMATCH[1]}"
    local sm="${BASH_REMATCH[2]}"
    local size
    size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
    echo "${version}|${sm}|${size}"
  fi
}

# ---------------------------------------------------------------------------
# remove_version — remove a versioned directory and its wrappers
# Args: $1 = versioned_dir, $2 = parent_bin_dir
# ---------------------------------------------------------------------------
remove_version() {
  local versioned_dir="$1"
  local parent_bin_dir="$2"
  
  info "Removing ${versioned_dir}..."
  rm -rf "$versioned_dir"
  
  # Remove wrapper scripts if they point to this version
  for binary in llama-cli llama-server llama-bench; do
    local wrapper_path="${parent_bin_dir}/${binary}"
    if [[ -f "$wrapper_path" ]]; then
      # Check if the wrapper points to the version we're removing
      if grep -q "INSTALL_DIR=\"${versioned_dir}\"" "$wrapper_path" 2>/dev/null; then
        rm -f "$wrapper_path"
        info "  Removed wrapper: ${wrapper_path}"
      fi
    fi
  done
  
  success "Removed $(basename "$versioned_dir")"
}

# ---------------------------------------------------------------------------
# confirm — prompt for yes/no confirmation
# Args: $1 = prompt message
# Returns: 0 if yes, 1 if no
# ---------------------------------------------------------------------------
confirm() {
  local prompt="$1"
  local answer
  
  read -r -p "$(echo -e "${YELLOW}${prompt} [y/N]:${RESET} ")" answer
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local install_dir="${HOME}/.local/bin/llama"
  local keep_count=""
  local remove_all=false
  local dry_run=false
  
  # --- parse arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-dir) install_dir="$2" ; shift 2 ;;
      --keep)        keep_count="$2"  ; shift 2 ;;
      --all)         remove_all=true  ; shift ;;
      --dry-run)     dry_run=true     ; shift ;;
      -h|--help)     usage ;;
      *)             error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done
  
  local parent_dir
  parent_dir="$(dirname "$install_dir")"
  
  # --- list installed versions ---
  local versions
  versions=$(list_installed_versions "$install_dir")
  
  if [[ -z "$versions" ]]; then
    info "No installed versions found in ${parent_dir}"
    exit 0
  fi
  
  local version_count
  version_count=$(echo "$versions" | wc -l)
  
  echo
  echo -e "${BOLD}Installed llama.cpp versions (${version_count} found):${RESET}"
  echo
  printf "  %-20s  %-6s  %-10s  %s\n" "Version" "SM" "Size" "Path"
  printf "  %-20s  %-6s  %-10s  %s\n" "-------" "--" "----" "----"
  
  local version_list=()
  while IFS= read -r ver_dir; do
    local info
    info=$(get_version_info "$ver_dir")
    if [[ -n "$info" ]]; then
      IFS='|' read -r ver sm size <<< "$info"
      printf "  %-20s  %-6s  %-10s  %s\n" "$ver" "$sm" "$size" "$ver_dir"
      version_list+=("$ver_dir")
    fi
  done <<< "$versions"
  
  echo
  
  # --- remove all ---
  if [[ "$remove_all" == "true" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would remove all ${version_count} versions"
      exit 0
    fi
    
    if ! confirm "Remove ALL ${version_count} versions?"; then
      info "Aborted."
      exit 0
    fi
    
    for ver_dir in "${version_list[@]}"; do
      remove_version "$ver_dir" "$parent_dir"
    done
    
    echo
    success "Removed all ${version_count} versions"
    exit 0
  fi
  
  # --- keep N most recent ---
  if [[ -n "$keep_count" ]]; then
    if [[ ! "$keep_count" =~ ^[0-9]+$ ]]; then
      error "Invalid --keep value: ${keep_count}. Must be a positive integer."
    fi
    
    local to_remove_count=$((version_count - keep_count))
    
    if [[ $to_remove_count -le 0 ]]; then
      info "Already have ${version_count} versions, keeping ${keep_count} — nothing to remove."
      exit 0
    fi
    
    echo -e "${YELLOW}Will keep the ${keep_count} most recent version(s) and remove ${to_remove_count} older version(s).${RESET}"
    echo
    
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would remove the following versions:"
      local idx=0
      for ver_dir in "${version_list[@]}"; do
        idx=$((idx + 1))
        if [[ $idx -gt $keep_count ]]; then
          info "  - $(basename "$ver_dir")"
        fi
      done
      exit 0
    fi
    
    if ! confirm "Proceed with removal?"; then
      info "Aborted."
      exit 0
    fi
    
    local idx=0
    local removed=0
    for ver_dir in "${version_list[@]}"; do
      idx=$((idx + 1))
      if [[ $idx -gt $keep_count ]]; then
        remove_version "$ver_dir" "$parent_dir"
        removed=$((removed + 1))
      fi
    done
    
    echo
    success "Removed ${removed} version(s), kept ${keep_count}"
    exit 0
  fi
  
  # --- interactive mode ---
  echo -e "${BOLD}Interactive cleanup${RESET}"
  echo "Select versions to remove (or press Ctrl+C to abort):"
  echo
  
  local removed=0
  for ver_dir in "${version_list[@]}"; do
    local ver_name
    ver_name=$(basename "$ver_dir")
    
    if confirm "Remove ${ver_name}?"; then
      if [[ "$dry_run" == "true" ]]; then
        info "[dry-run] Would remove ${ver_dir}"
      else
        remove_version "$ver_dir" "$parent_dir"
      fi
      removed=$((removed + 1))
    fi
  done
  
  echo
  if [[ $removed -eq 0 ]]; then
    info "No versions removed."
  else
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would have removed ${removed} version(s)"
    else
      success "Removed ${removed} version(s)"
    fi
  fi
}

main "$@"
