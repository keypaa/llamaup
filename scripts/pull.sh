#!/usr/bin/env bash
# pull.sh — Detect the local GPU, find the matching pre-built binary on GitHub
# Releases, download it, verify the checksum, and install it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import GPU detection helpers from detect.sh
# shellcheck source=scripts/detect.sh
source "${SCRIPT_DIR}/detect.sh"

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
# download_file — download a URL to a destination path with progress
# Args:
#   $1 = url
#   $2 = dest_path
# Exits 1 on curl failure.
# ---------------------------------------------------------------------------
download_file() {
  local url="$1"
  local dest_path="$2"

  # -L follows redirects, --progress-bar shows a progress bar,
  # -o writes to file, -f fails on HTTP errors
  curl -L --progress-bar -f -o "$dest_path" "$url" || {
    # Clean up partial download
    rm -f "$dest_path"
    error "Download failed from:\n  ${url}\n  → Check your internet connection."
  }
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

  for binary in llama-cli llama-server llama-bench; do
    local bin_path="${install_dir}/bin/${binary}"
    if [[ -f "$bin_path" ]]; then
      ln -sf "$bin_path" "${bin_dir}/${binary}"
      success "Symlinked: ${bin_dir}/${binary} → ${bin_path}"
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
  local gpu_map="${SCRIPT_DIR}/../configs/gpu_map.json"

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

  info "Downloading ${asset_name}..."
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

  echo
  success "Installed to: ${versioned_dir}"
  echo -e "  Add to your PATH: export PATH=\"\$(dirname \"$install_dir\"):\$PATH\""
  echo
}

main "$@"