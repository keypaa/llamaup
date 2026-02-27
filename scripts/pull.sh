#!/usr/bin/env bash
# pull.sh — Detect the local GPU, find the matching pre-built binary on GitHub
# Releases, download it, verify the checksum, and install it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import GPU detection helpers from detect.sh
# shellcheck source=scripts/detect.sh
source "${SCRIPT_DIR}/detect.sh"

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
Usage: pull.sh [OPTIONS]

Detect the local GPU, find the matching pre-built llama.cpp binary on GitHub
Releases, download it, verify the SHA256 checksum, and install it.

Options:
  --version <tag>       llama.cpp release tag. Default: latest.
  --repo <owner/repo>   GitHub repo to pull from. Overrides LLAMA_DEPLOY_REPO.
  --sm <version>        Override SM version (skip auto-detection).
  --install-dir <dir>   Install destination. Default: ~/.local/bin/llama
  --no-verify           Skip SHA256 verification (not recommended).
  --dry-run             Show what would be downloaded, without downloading.
  --list                List all available binaries for this version and exit.
  --force               Re-download even if binary already installed.
  -h, --help            Show this help.

Environment variables:
  LLAMA_DEPLOY_REPO     GitHub repo to pull from
  LLAMA_DEPLOY_DEBUG    Set to 1 for verbose output

Examples:
  ./scripts/pull.sh
  ./scripts/pull.sh --version b4200 --sm 89
  ./scripts/pull.sh --list --repo my-org/llamaup
  ./scripts/pull.sh --dry-run
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
# cleanup_on_interrupt — remove partial downloads on Ctrl+C
# ---------------------------------------------------------------------------
cleanup_on_interrupt() {
  echo
  warn "Download interrupted. Cleaning up partial files..."
  if [[ -n "${CLEANUP_FILE:-}" ]] && [[ -f "$CLEANUP_FILE" ]]; then
    rm -f "$CLEANUP_FILE"
    info "Removed partial download: $CLEANUP_FILE"
  fi
  exit 130
}

# ---------------------------------------------------------------------------
# validate_sm — verify that an SM version exists in gpu_map.json
# Args: $1 = sm_version (e.g. "89"), $2 = path to gpu_map.json
# Returns: 0 if valid, 1 if invalid
# ---------------------------------------------------------------------------
validate_sm() {
  local sm="$1"
  local gpu_map="$2"
  
  if ! jq -e --arg sm "$sm" '.gpu_families | to_entries[] | select(.value.sm == $sm)' "$gpu_map" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# check_deps — verify curl, jq, and tar are available
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()
  for tool in curl jq tar; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Error: missing required tools: ${missing[*]}${RESET}" >&2
    echo "  → Install missing tools and re-run." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# fetch_release_json — fetch full release JSON from GitHub API
# Args:
#   $1 = github_repo (e.g. "my-org/llamaup")
#   $2 = version ("latest" resolves to the latest release, else exact tag)
# Returns: full release JSON on stdout
# Exits 1 on API failure or release not found.
# ---------------------------------------------------------------------------
fetch_release_json() {
  local github_repo="$1"
  local version="$2"
  local url

  if [[ "$version" == "latest" ]]; then
    url="https://api.github.com/repos/${github_repo}/releases/latest"
  else
    url="https://api.github.com/repos/${github_repo}/releases/tags/${version}"
  fi

  local response
  response=$(curl -fsSL "$url" 2>/dev/null) || {
    error "Failed to fetch release info from:\n  ${url}\n  → Check your internet connection or verify the repo with --repo."
  }

  # Check for GitHub's "Not Found" response
  if echo "$response" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
    error "Release '${version}' not found on ${github_repo}.\n  → Run with --list to see available versions."
  fi

  echo "$response"
}

# ---------------------------------------------------------------------------
# find_asset — locate the right asset in release JSON for a given SM version
# Matching rule: asset name must contain "sm{sm}" AND "linux" AND NOT ".sha256"
# Args:
#   $1 = release_json
#   $2 = sm_version (e.g. "89")
# Returns: "<asset_name>|<asset_url>" or empty string if not found
# ---------------------------------------------------------------------------
find_asset() {
  local release_json="$1"
  local sm_version="$2"

  local result
  result=$(echo "$release_json" | jq -r \
    --arg sm "sm${sm_version}" \
    '.assets[] |
     select(
       (.name | contains($sm)) and
       (.name | ascii_downcase | contains("linux")) and
       (.name | endswith(".sha256") | not)
     ) |
     "\(.name)|\(.browser_download_url)"' \
  | head -n1)

  echo "$result"
}

# ---------------------------------------------------------------------------
# download_file — download a URL to a destination path with a live block progress bar
# Args:
#   $1 = url
#   $2 = dest_path
# Exits 1 on curl failure.
# ---------------------------------------------------------------------------

# _hr_bytes — format a byte count as a human-readable string (K / M / G)
# Args: $1 = bytes (integer)
_hr_bytes() {
  local b="$1"
  if   [[ "$b" -ge 1073741824 ]]; then awk "BEGIN {printf \"%.1fG\", $b/1073741824}"
  elif [[ "$b" -ge 1048576    ]]; then awk "BEGIN {printf \"%.0fM\", $b/1048576}"
  else                                  awk "BEGIN {printf \"%.0fK\", $b/1024}"
  fi
}

# _build_bar — emit a block bar of bar_width chars filled to percent %
# Args: $1 = percent (0-100), $2 = bar_width
_build_bar() {
  local pct="$1" width="$2"
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  local i
  for (( i = 0; i < filled; i++ )); do bar+="█"; done
  for (( i = 0; i < empty;  i++ )); do bar+="░"; done
  printf '%s' "$bar"
}

download_file() {
  local url="$1"
  local dest_path="$2"
  local filename
  filename="$(basename "$dest_path")"

  echo -e "${CYAN}Downloading:${RESET} ${filename}"

  # ensure destination directory exists
  mkdir -p "$(dirname "$dest_path")"

  # -----------------------------------------------------------------------
  # Fetch Content-Length by following all redirects with a HEAD request.
  # Use awk to pick the LAST "content-length:" header line (case-insensitive,
  # strips \r from CRLF HTTP headers).  Falls back to 0 if not present.
  # -----------------------------------------------------------------------
  local total_size=0
  total_size=$(curl -sI -L --max-redirs 10 "$url" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1) == "content-length:" { last = $2+0 } END { print (last ? last : 0) }')
  : "${total_size:=0}"

  # start curl quietly in background; redirect stderr so set -e is not triggered
  curl -L -f -s -o "$dest_path" "$url" 2>/dev/null &
  local curl_pid=$!

  local bar_width=30
  local last_percent=-1
  local spin_idx=0
  local spin_chars=('-' '\' '|' '/')

  # monitor file growth until curl exits
  while kill -0 "$curl_pid" 2>/dev/null; do
    local current_size=0
    if [[ -f "$dest_path" ]]; then
      # Linux stat first (WSL), then macOS fallback
      current_size=$(stat -c%s "$dest_path" 2>/dev/null \
                  || stat -f%z "$dest_path" 2>/dev/null \
                  || echo 0)
    fi

    local dl_str
    dl_str="$(_hr_bytes "$current_size")"

    if [[ "$total_size" =~ ^[0-9]+$ ]] && [[ "$total_size" -gt 0 ]]; then
      # ---- determinate bar ----
      local percent=$(( current_size * 100 / total_size ))
      [[ "$percent" -gt 100 ]] && percent=100

      if [[ "$percent" -ne "$last_percent" ]]; then
        last_percent="$percent"
        local bar tot_str
        bar="$(_build_bar "$percent" "$bar_width")"
        tot_str="$(_hr_bytes "$total_size")"
        printf "\r${GREEN}%3d%%${RESET}|${CYAN}%s${RESET}| ${BOLD}%s${RESET}/${BOLD}%s${RESET}  " \
          "$percent" "$bar" "$dl_str" "$tot_str"
      fi
    else
      # ---- indeterminate spinner (size unknown) ----
      local spin="${spin_chars[$((spin_idx % 4))]}"
      (( spin_idx++ )) || true
      printf "\r${CYAN}%s${RESET} Downloading... ${BOLD}%s${RESET}       " "$spin" "$dl_str"
    fi

    sleep 0.2
  done

  wait "$curl_pid"
  local exit_code=$?

  if [[ "$exit_code" -eq 0 ]] && [[ -f "$dest_path" ]] && [[ -s "$dest_path" ]]; then
    # Final 100% line
    local final_size final_str full_bar
    final_size=$(stat -c%s "$dest_path" 2>/dev/null \
              || stat -f%z "$dest_path" 2>/dev/null \
              || echo 0)
    final_str="$(_hr_bytes "$final_size")"
    full_bar="$(_build_bar 100 "$bar_width")"
    printf "\r${GREEN}%3d%%${RESET}|${CYAN}%s${RESET}| ${BOLD}%s${RESET}/${BOLD}%s${RESET}  \n" \
      "100" "$full_bar" "$final_str" "$final_str"
    success "Downloaded ${filename}"
  else
    echo
    rm -f "$dest_path"
    error "Download failed from:\n  ${url}\n  → Check your internet connection."
  fi
}

# ---------------------------------------------------------------------------
# verify_checksum — verify a file against its SHA256 from a URL
# Args:
#   $1 = file_path
#   $2 = sha256_url (URL to a .sha256 file)
# Exits 1 if hash doesn't match. Prints both expected and actual on failure.
# ---------------------------------------------------------------------------
verify_checksum() {
  local file_path="$1"
  local sha256_url="$2"

  info "Fetching checksum from ${sha256_url}..."
  local expected_line
  expected_line=$(curl -fsSL "$sha256_url" 2>/dev/null) || {
    error "Failed to fetch SHA256 from:\n  ${sha256_url}"
  }

  # .sha256 files contain "<hash>  <filename>" — extract just the hash
  local expected_hash
  expected_hash=$(echo "$expected_line" | awk '{print $1}')

  local actual_hash
  actual_hash=$(sha256sum "$file_path" | awk '{print $1}')

  if [[ "$expected_hash" != "$actual_hash" ]]; then
    echo -e "${RED}SHA256 mismatch!${RESET}" >&2
    echo "  Expected : $expected_hash" >&2
    echo "  Actual   : $actual_hash" >&2
    rm -f "$file_path"
    error "Deleted corrupt download. Re-run to try again."
  fi

  success "SHA256 verified ✓"
}

# ---------------------------------------------------------------------------
# install_binary — extract tarball and create symlinks for main binaries
# Symlinks: llama-cli, llama-server, llama-bench (if present in archive)
# Args:
#   $1 = archive_path
#   $2 = install_dir
# ---------------------------------------------------------------------------
install_binary() {
  local archive_path="$1"
  local install_dir="$2"

  info "Installing to ${install_dir}..."
  mkdir -p "$install_dir"

  # Extract with --strip-components=1 to flatten one level of directory nesting
  tar -xzf "$archive_path" -C "$install_dir" --strip-components=1 \
    || error "Failed to extract archive: ${archive_path}"

  # Create symlinks for the main binaries in the install_dir's parent
  # (so users can add one directory to PATH)
  local bin_dir
  bin_dir="$(dirname "$install_dir")"

  # Ensure installed binaries are executable but not world-writable.
  # Use 0755: owner rwx, group rx, others rx — sufficient for CLI binaries.
  if [[ -d "${install_dir}/bin" ]]; then
    find "${install_dir}/bin" -maxdepth 1 -type f -exec chmod 755 {} \;
    success "Set executable permissions: ${install_dir}/bin/* -> 755"
  fi

  for binary in llama-cli llama-server llama-bench; do
    local bin_path="${install_dir}/bin/${binary}"
    if [[ -f "$bin_path" ]]; then
      # Create a small wrapper script in the parent bin dir that sets
      # LD_LIBRARY_PATH to include the package's lib directory so users
      # don't need to set environment variables themselves.
      local wrapper_path="${bin_dir}/${binary}"
      
      # Build LD_LIBRARY_PATH components that actually exist
      local ld_path_parts=()
      [[ -d "${install_dir}/lib" ]] && ld_path_parts+=("\$INSTALL_DIR/lib")
      [[ -d "${install_dir}/bin" ]] && ld_path_parts+=("\$INSTALL_DIR/bin")
      local ld_path_str
      ld_path_str=$(IFS=:; echo "${ld_path_parts[*]}")

      cat > "$wrapper_path" <<EOF
#!/usr/bin/env bash
# Wrapper generated by pull.sh — sets LD_LIBRARY_PATH for this package
INSTALL_DIR="${install_dir}"
export LD_LIBRARY_PATH="${ld_path_str}:\${LD_LIBRARY_PATH:-}"
exec "\$INSTALL_DIR/bin/${binary}" "\$@"
EOF

      chmod 755 "$wrapper_path"
      success "Installed wrapper: ${wrapper_path} → ${bin_path}"
    fi
  done
}

# ---------------------------------------------------------------------------
# list_available — print all non-.sha256 assets for a release
# Args: $1 = release_json
# ---------------------------------------------------------------------------
list_available() {
  local release_json="$1"

  echo
  echo -e "${BOLD}Available binaries:${RESET}"
  echo

  echo "$release_json" | jq -r \
    '.assets[] |
     select(.name | endswith(".sha256") | not) |
     "  " + .name' \
  || error "Failed to parse release JSON."

  echo
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local llama_version="latest"
  local github_repo="${LLAMA_DEPLOY_REPO:-}"
  local sm_version=""
  local install_dir="${HOME}/.local/bin/llama"
  local do_verify=true
  local dry_run=false
  local do_list=false
  local force=false
  local dev_mode=false
  local gpu_map="${SCRIPT_DIR}/../configs/gpu_map.json"
  
  # Set up trap for cleanup on interrupt
  trap cleanup_on_interrupt INT TERM

  # --- parse arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)     llama_version="$2" ; shift 2 ;;
      --repo)        github_repo="$2"   ; shift 2 ;;
      --sm)          sm_version="$2"    ; shift 2 ;;
      --install-dir) install_dir="$2"   ; shift 2 ;;
      --no-verify)   do_verify=false    ; shift ;;
      --dry-run)     dry_run=true       ; shift ;;
      --list)        do_list=true       ; shift ;;
      --force)       force=true         ; shift ;;
      --dev-sm)      sm_version="$2" ; dev_mode=true ; force=true ; shift 2 ;;
      -h|--help)     usage ;;
      *)             error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done

  if [[ "${LLAMA_DEPLOY_DEBUG:-}" == "1" ]]; then
    set -x
  fi

  # --- require repo before any network calls ---
  if [[ -z "$github_repo" ]]; then
    error "No GitHub repo specified.\n  → Use --repo or set LLAMA_DEPLOY_REPO (e.g. my-org/llamaup)."
  fi

  check_deps

  # --- validate gpu_map path ---
  if [[ ! -f "$gpu_map" ]]; then
    error "gpu_map.json not found at: ${gpu_map}\n  → Check your installation."
  fi

  # --- dev mode banner ---
  if [[ "$dev_mode" == "true" ]]; then
    echo
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║  DEV MODE  --dev-sm ${sm_version}$(printf '%*s' $((28 - ${#sm_version})) '')║${RESET}"
    echo -e "${YELLOW}║  GPU detection bypassed · force re-download  ║${RESET}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${RESET}"
    echo
  fi

  # --- resolve SM version ---
  if [[ -z "$sm_version" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would auto-detect SM version from local GPU"
      sm_version="<auto>"
    else
      local gpu_names first_gpu
      gpu_names=$(get_gpu_names) || {
        error "No GPU detected. Use --sm to specify the SM version manually."
      }
      first_gpu=$(echo "$gpu_names" | head -n1)
      sm_version=$(lookup_sm "$first_gpu" "$gpu_map")
      if [[ -z "$sm_version" ]]; then
        error "GPU '${first_gpu}' not found in gpu_map.json.\n  → Use --sm to specify the SM version.\n  → Or build from source: ./scripts/build.sh --sm <version>"
      fi
      info "Detected GPU: ${first_gpu} (SM ${sm_version})"
    fi
  elif [[ "$dev_mode" == "false" ]]; then
    # Validate user-provided SM version (skip in dev mode)
    if ! validate_sm "$sm_version" "$gpu_map"; then
      error "Invalid SM version: ${sm_version}\n  → Valid SM versions: $(jq -r '.gpu_families | to_entries[] | .value.sm' "$gpu_map" | sort -n | paste -sd, -)\n  → Run ./scripts/detect.sh to see your GPU's SM version"
    fi
  fi

  # --- fetch release JSON ---
  local release_json
  if [[ "$dry_run" == "true" && "$do_list" == "false" ]]; then
    echo
    echo -e "${BOLD}[llamaup pull — DRY RUN]${RESET}"
    echo
    echo -e "  Repo          : ${github_repo}"
    echo -e "  Version       : ${llama_version}"
    echo -e "  SM version    : ${sm_version}"
    echo -e "  Install dir   : ${install_dir}"
    echo -e "  Verify SHA256 : ${do_verify}"
    echo
    echo -e "  Steps that would run:"
    echo -e "    1. Fetch release info for ${llama_version} from GitHub"
    echo -e "    2. Find asset matching sm${sm_version} + linux"
    echo -e "    3. Download to /tmp/"
    echo -e "    4. Verify SHA256"
    echo -e "    5. Extract to ${install_dir}"
    echo -e "    6. Symlink llama-cli, llama-server, llama-bench"
    echo -e "    7. Set executable permissions (chmod 755) on installed binaries"
    echo
    exit 0
  fi

  info "Fetching release info for ${llama_version} from ${github_repo}..."
  release_json=$(fetch_release_json "$github_repo" "$llama_version")

  # --- --list mode: print assets and exit ---
  if [[ "$do_list" == "true" ]]; then
    list_available "$release_json"
    exit 0
  fi

  # --- find the right asset ---
  local asset_info
  asset_info=$(find_asset "$release_json" "$sm_version")

  if [[ -z "$asset_info" ]]; then
    echo -e "${RED}Error: No binary found for SM ${sm_version} in this release.${RESET}" >&2
    echo "  Available binaries:" >&2
    echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".sha256") | not) | "    " + .name' >&2
    echo >&2
    echo "  → Build for your GPU: ./scripts/build.sh --sm ${sm_version}" >&2
    exit 1
  fi

  local asset_name asset_url
  asset_name=$(echo "$asset_info" | cut -d'|' -f1)
  asset_url=$(echo "$asset_info"  | cut -d'|' -f2)

  # --- idempotency check ---
  local versioned_dir="${install_dir}-${llama_version}-sm${sm_version}"
  if [[ -d "$versioned_dir" && "$force" == "false" ]]; then
    warn "Already installed at ${versioned_dir}."
    warn "Run with --force to re-download."
    exit 0
  fi

  # --- check install dir is writable ---
  local parent_install_dir
  parent_install_dir="$(dirname "$install_dir")"
  mkdir -p "$parent_install_dir" 2>/dev/null || \
    error "Cannot create install directory: ${parent_install_dir}\n  → Check permissions."

  if [[ ! -w "$parent_install_dir" ]]; then
    error "Install directory is not writable: ${parent_install_dir}\n  → Try: sudo chown -R \$(whoami) ${parent_install_dir}"
  fi

  # --- download ---
  local tmp_archive="/tmp/${asset_name}"
  # If a partial download exists, remove it
  [[ -f "$tmp_archive" ]] && rm -f "$tmp_archive"

  # Set cleanup variable for trap handler
  CLEANUP_FILE="$tmp_archive"
  
  # download_file will print its own progress message
  download_file "$asset_url" "$tmp_archive"

  # --- verify checksum ---
  if [[ "$do_verify" == "true" ]]; then
    local sha256_url="${asset_url}.sha256"
    verify_checksum "$tmp_archive" "$sha256_url"
  else
    warn "Skipping SHA256 verification (--no-verify)."
  fi

  # --- install ---
  install_binary "$tmp_archive" "$versioned_dir"
  rm -f "$tmp_archive"
  
  # Clear cleanup variable after successful install
  CLEANUP_FILE=""

  echo
  success "Installed to: ${versioned_dir}"
  echo
  echo -e "  ${BOLD}Next steps:${RESET}"
  # Show the actual resolved path, not the variable
  local bin_parent_dir
  bin_parent_dir="$(dirname "$install_dir")"
  echo -e "    1. Add to PATH: ${CYAN}export PATH=\"${bin_parent_dir}:\$PATH\"${RESET}"
  echo -e "    2. Run with auto-download: ${CYAN}llama-cli -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M -cnv${RESET}"
  echo
  echo -e "  ${BOLD}Available tools:${RESET}"
  echo -e "    llama-cli --help                    # Command-line inference (see --help for all flags)"
  echo -e "    llama-server -m model.gguf          # Start HTTP API server (recommended for chat)"
  echo -e "    llama-bench -m model.gguf           # Benchmark performance"
  echo
  echo -e "  ${BOLD}Quick examples:${RESET}"
  echo -e "    llama-cli -hf user/repo:Q4_K_M -cnv             # Auto-download + interactive chat"
  echo -e "    llama-cli -m model.gguf -p \"Hello!\" -n 512     # One-shot prompt"
  echo -e "    llama-server -m model.gguf -c 8192 --port 8080  # Start web UI + API"
  echo
  echo -e "  See README.md for full usage guide: ${CYAN}https://github.com/${github_repo}#using-llamacpp-quick-reference${RESET}"
  echo
}

main "$@"