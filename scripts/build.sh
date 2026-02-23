#!/usr/bin/env bash
# build.sh — Compile llama.cpp for a specific SM version, package as a
# versioned tarball, and optionally upload to GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source detect.sh to import lookup_sm() and detect_cuda_version().
# The BASH_SOURCE guard in detect.sh ensures main() is NOT executed on source.
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
# Defaults
# ---------------------------------------------------------------------------
readonly LLAMA_REPO_URL="https://github.com/ggerganov/llama.cpp.git"
readonly LLAMA_GITHUB_API="https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"

# ---------------------------------------------------------------------------
# usage — print CLI help and exit 0
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: build.sh [OPTIONS]

Compile llama.cpp from source for a given SM (CUDA arch) version, package it
as a versioned tarball, and optionally upload it to GitHub Releases.

Options:
  --sm <version>        SM version to build for (e.g. 89). Auto-detected if omitted.
  --version <tag>       llama.cpp release tag (e.g. b4200). Default: latest.
  --cuda <version>      CUDA version string for binary name. Default: auto-detected.
  --output <dir>        Output directory for the tarball. Default: ./dist
  --upload              Upload binary to GitHub Releases after building.
  --repo <owner/repo>   GitHub repo for upload. Overrides LLAMA_DEPLOY_REPO env var.
  --jobs <n>            Parallel build jobs. Default: nproc.
  --src-dir <dir>       Where to clone llama.cpp. Default: /tmp/llamaup-src
  --dry-run             Print what would happen without executing.
  -h, --help            Show this help.

Environment variables:
  LLAMA_DEPLOY_REPO     GitHub repo (owner/repo) for releases
  GITHUB_TOKEN          Required when using --upload
  LLAMA_DEPLOY_DEBUG    Set to 1 for verbose output

Examples:
  ./scripts/build.sh --sm 89 --version b4200
  ./scripts/build.sh --dry-run --sm 89 --version b4200
  ./scripts/build.sh --sm 89 --upload --repo my-org/llamaup
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# error — print a red error message to stderr and exit 1
# ---------------------------------------------------------------------------
error() {
  echo -e "${RED}Error: $1${RESET}" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# info / success / warn — coloured log helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}→ $1${RESET}"; }
success() { echo -e "${GREEN}✓ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}" >&2; }

# ---------------------------------------------------------------------------
# verify_archive — verify that an archive is valid and matches its SHA256
# Args: $1 = archive_path (path to .tar.gz file)
# Returns: 0 if valid, 1 if invalid or corrupt
# Does NOT exit — caller decides what to do
# ---------------------------------------------------------------------------
verify_archive() {
  local archive_path="$1"
  local sha256_path="${archive_path}.sha256"

  # Check 1: File must not be empty
  if [[ ! -s "$archive_path" ]]; then
    warn "Archive exists but is empty: ${archive_path}"
    return 1
  fi

  # Check 2: Must be a valid tarball
  if ! tar -tzf "$archive_path" >/dev/null 2>&1; then
    warn "Archive exists but is corrupt or not a valid tarball: ${archive_path}"
    return 1
  fi

  # Check 3: Verify SHA256 if .sha256 file exists
  if [[ -f "$sha256_path" ]]; then
    local expected_hash actual_hash
    expected_hash=$(awk '{print $1}' "$sha256_path")
    actual_hash=$(sha256sum "$archive_path" | awk '{print $1}')

    if [[ "$expected_hash" != "$actual_hash" ]]; then
      warn "Archive SHA256 mismatch:"
      warn "  Expected: ${expected_hash}"
      warn "  Actual:   ${actual_hash}"
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# check_deps — verify all required tools are present
# Args: $1 = upload_flag ("true" or "false")
# Exits 1 with a list of missing tools if any are absent.
# ---------------------------------------------------------------------------
check_deps() {
  local upload_flag="$1"
  local missing=()

  for tool in git cmake ninja jq nvcc curl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  if [[ "$upload_flag" == "true" ]]; then
    command -v gh >/dev/null 2>&1 || missing+=("gh (GitHub CLI)")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Error: missing required tools:${RESET}" >&2
    for tool in "${missing[@]}"; do
      echo "  - $tool" >&2
    done
    echo "  → Install missing tools and re-run." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# check_upload_auth — fail fast if --upload is set but gh is not authenticated
# ---------------------------------------------------------------------------
check_upload_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    error "GitHub CLI is not authenticated.\n  → Run: gh auth login\n  → Or set GITHUB_TOKEN in your environment."
  fi
}

# ---------------------------------------------------------------------------
# fetch_latest_version — resolve "latest" to an actual llama.cpp release tag
# Returns: tag string like "b4200" on stdout
# Exits 1 if the API call fails.
# ---------------------------------------------------------------------------
fetch_latest_version() {
  local tag
  tag=$(curl -fsSL "$LLAMA_GITHUB_API" \
        | jq -r '.tag_name') || {
    error "Failed to fetch latest llama.cpp release from GitHub API.\n  → Check your internet connection or specify --version manually."
  }

  if [[ -z "$tag" || "$tag" == "null" ]]; then
    error "GitHub API returned no tag_name. Try specifying --version manually."
  fi

  echo "$tag"
}

# ---------------------------------------------------------------------------
# verify_version_exists — check that a given tag exists on the llama.cpp repo
# Args: $1 = tag
# Exits 1 if not found.
# ---------------------------------------------------------------------------
verify_version_exists() {
  local tag="$1"
  local http_status
  http_status=$(curl -o /dev/null -sI -w "%{http_code}" \
    "https://api.github.com/repos/ggerganov/llama.cpp/releases/tags/${tag}")

  if [[ "$http_status" != "200" ]]; then
    error "llama.cpp release tag '${tag}' not found on GitHub (HTTP ${http_status}).\n  → Check available tags at: https://github.com/ggerganov/llama.cpp/releases"
  fi
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
# detect_sm — auto-detect SM version from the local GPU
# Internally reuses lookup_sm() imported from detect.sh.
# Args: $1 = path to gpu_map.json
# Returns: SM string like "89" on stdout
# Exits 1 if no GPU found or SM unknown.
# ---------------------------------------------------------------------------
detect_sm() {
  local gpu_map="$1"
  local gpu_names sm

  gpu_names=$(get_gpu_names) || {
    error "No GPU detected. Use --sm to specify the SM version manually."
  }

  # Use the first GPU for SM detection
  local first_gpu
  first_gpu=$(echo "$gpu_names" | head -n1)

  sm=$(lookup_sm "$first_gpu" "$gpu_map")

  if [[ -z "$sm" ]]; then
    error "GPU '${first_gpu}' not found in gpu_map.json.\n  → Use --sm to specify the SM version manually.\n  → Or open an issue: https://github.com/keypaa/llamaup/issues"
  fi

  echo "$sm"
}

# ---------------------------------------------------------------------------
# prepare_source — clone llama.cpp or fetch + checkout if already cloned
# Args:
#   $1 = target_version (tag, e.g. "b4200")
#   $2 = src_dir (path to clone into)
# Exits 1 on git failure.
# ---------------------------------------------------------------------------
prepare_source() {
  local target_version="$1"
  local src_dir="$2"

  if [[ -d "${src_dir}/.git" ]]; then
    info "llama.cpp source already cloned at ${src_dir} — fetching latest tags..."
    git -C "$src_dir" fetch --tags --quiet || error "git fetch failed in ${src_dir}."
  else
    info "Cloning llama.cpp at tag ${target_version}..."
    mkdir -p "$(dirname "$src_dir")"
    git clone --filter=blob:none --no-checkout --quiet \
      "$LLAMA_REPO_URL" "$src_dir" \
      || error "git clone failed. Check your internet connection."
  fi

  info "Checking out ${target_version}..."
  git -C "$src_dir" checkout --quiet "${target_version}" \
    || error "Tag '${target_version}' not found in repo. Try fetching with --version again."
}

# ---------------------------------------------------------------------------
# build — run cmake configure + build + install
# Args:
#   $1 = src_dir
#   $2 = sm_version (e.g. "89")
#   $3 = build_jobs (number of parallel jobs)
#   $4 = install_dir (where to install binaries)
# Exits 1 on cmake or build failure.
# ---------------------------------------------------------------------------
build() {
  local src_dir="$1"
  local sm_version="$2"
  local build_jobs="$3"
  local install_dir="$4"
  local build_dir="${src_dir}/build-sm${sm_version}"

  # Clean a stale build directory from a previous failed attempt
  if [[ -d "$build_dir" ]]; then
    warn "Stale build directory found at ${build_dir} — cleaning..."
    rm -rf "$build_dir"
  fi

  mkdir -p "$build_dir" "$install_dir"

  info "Configuring (SM ${sm_version})..."
  cmake -S "$src_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="${sm_version}" \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DLLAMA_CURL=ON \
    -DLLAMA_OPENSSL=ON \
    -G Ninja \
    2>&1 || error "cmake configure failed.\n  → Check that CUDA toolkit is installed and nvcc is in PATH.\n  → OpenSSL dev files required for HTTPS: apt install libssl-dev (Debian/Ubuntu) or yum install openssl-devel (RHEL/CentOS)\n  → libcurl dev files required: apt install libcurl4-openssl-dev (Debian/Ubuntu) or yum install libcurl-devel (RHEL/CentOS)\n  → Try: nvcc --version"

  info "Compiling with ${build_jobs} jobs..."
  cmake --build "$build_dir" --parallel "$build_jobs" \
    2>&1 || error "cmake build failed.\n  → Check the output above for compile errors."

  info "Installing to ${install_dir}..."
  cmake --install "$build_dir" \
    2>&1 || error "cmake install failed."

  success "Build complete → ${install_dir}"
}

# ---------------------------------------------------------------------------
# package — create a named tarball and generate a paired SHA256 file
# Args:
#   $1 = install_dir
#   $2 = sm_version
#   $3 = llama_version
#   $4 = cuda_version
#   $5 = output_dir
# Returns: absolute path to the created .tar.gz file (echoed to stdout)
# Naming: llama-{version}-linux-cuda{cuda_ver}-sm{sm}-x64.tar.gz
# ---------------------------------------------------------------------------
package() {
  local install_dir="$1"
  local sm_version="$2"
  local llama_version="$3"
  local cuda_version="$4"
  local output_dir="$5"

  local archive_name="llama-${llama_version}-linux-cuda${cuda_version}-sm${sm_version}-x64.tar.gz"
  local archive_path
  archive_path="$(realpath "$output_dir")/${archive_name}"

  mkdir -p "$output_dir"

  info "Packaging → ${archive_name}..."
  tar -czf "$archive_path" -C "$(dirname "$install_dir")" "$(basename "$install_dir")" \
    || error "tar failed while packaging."

  info "Generating SHA256..."
  # sha256sum outputs: "<hash>  <filename>"
  # We store only the hash in the .sha256 file (portable format)
  local hash
  hash=$(sha256sum "$archive_path" | awk '{print $1}')
  echo "$hash  ${archive_name}" > "${archive_path}.sha256"

  success "Package created: ${archive_path}"
  success "SHA256: ${archive_path}.sha256"

  echo "$archive_path"
}

# ---------------------------------------------------------------------------
# upload_release — upload the tarball and .sha256 to a GitHub Release.
# Creates the release if it does not exist.
# Args:
#   $1 = archive_path (absolute path to .tar.gz)
#   $2 = llama_version (e.g. "b4200")
#   $3 = github_repo (e.g. "my-org/llamaup")
# Exits 1 if gh CLI not authenticated or upload fails.
# ---------------------------------------------------------------------------
upload_release() {
  local archive_path="$1"
  local llama_version="$2"
  local github_repo="$3"

  info "Uploading to GitHub Release ${llama_version} on ${github_repo}..."

  # Create the release if it doesn't exist; --notes "" avoids interactive prompt
  if ! gh release view "$llama_version" --repo "$github_repo" >/dev/null 2>&1; then
    info "Release ${llama_version} not found — creating it..."
    gh release create "$llama_version" \
      --repo "$github_repo" \
      --title "llama.cpp ${llama_version}" \
      --notes "Pre-built CUDA binaries for llama.cpp ${llama_version}. Built by llamaup." \
      || error "Failed to create GitHub Release ${llama_version}."
  fi

  # Upload the tarball and its checksum
  gh release upload "$llama_version" \
    "$archive_path" \
    "${archive_path}.sha256" \
    --repo "$github_repo" \
    --clobber \
    || error "Failed to upload assets to GitHub Release ${llama_version}."

  success "Uploaded to: https://github.com/${github_repo}/releases/tag/${llama_version}"
}

# ---------------------------------------------------------------------------
# cleanup_on_interrupt — remove partial downloads/builds on Ctrl+C
# ---------------------------------------------------------------------------
cleanup_on_interrupt() {
  echo
  warn "Build interrupted. Cleaning up partial files..."
  # Remove partial archives if they exist
  if [[ -n "${CLEANUP_ARCHIVE:-}" ]] && [[ -f "$CLEANUP_ARCHIVE" ]]; then
    rm -f "$CLEANUP_ARCHIVE" "$CLEANUP_ARCHIVE.sha256"
    info "Removed partial archive: $CLEANUP_ARCHIVE"
  fi
  exit 130
}

# ---------------------------------------------------------------------------
# main — orchestrate the full build pipeline
# ---------------------------------------------------------------------------
main() {
  local sm_version=""
  local llama_version="latest"
  local cuda_version=""
  local output_dir="./dist"
  local do_upload=false
  local github_repo="${LLAMA_DEPLOY_REPO:-}"
  local build_jobs
  build_jobs=$(nproc 2>/dev/null || echo "4")
  local src_dir="/tmp/llamaup-src"
  local dry_run=false
  local gpu_map="${SCRIPT_DIR}/../configs/gpu_map.json"
  
  # Set up trap for cleanup on interrupt
  trap cleanup_on_interrupt INT TERM

  # --- parse arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sm)        sm_version="$2"  ; shift 2 ;;
      --version)   llama_version="$2" ; shift 2 ;;
      --cuda)      cuda_version="$2" ; shift 2 ;;
      --output)    output_dir="$2"  ; shift 2 ;;
      --upload)    do_upload=true   ; shift ;;
      --repo)      github_repo="$2" ; shift 2 ;;
      --jobs)      build_jobs="$2"  ; shift 2 ;;
      --src-dir)   src_dir="$2"     ; shift 2 ;;
      --dry-run)   dry_run=true     ; shift ;;
      -h|--help)   usage ;;
      *)           error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done

  if [[ "${LLAMA_DEPLOY_DEBUG:-}" == "1" ]]; then
    set -x
  fi

  # --- validate gpu_map path ---
  if [[ ! -f "$gpu_map" ]]; then
    error "gpu_map.json not found at: ${gpu_map}\n  → Use --gpu-map or check your installation."
  fi

  # --- fail fast: upload auth check before any slow work ---
  if [[ "$do_upload" == "true" ]]; then
    if [[ -z "$github_repo" ]]; then
      error "No GitHub repo specified.\n  → Use --repo or set LLAMA_DEPLOY_REPO."
    fi
    if [[ "$dry_run" == "false" ]]; then
      check_deps "true"
      check_upload_auth
    else
      info "[dry-run] Would verify gh CLI authentication"
    fi
  else
    if [[ "$dry_run" == "false" ]]; then
      check_deps "false"
    fi
  fi

  # --- resolve version ---
  if [[ "$llama_version" == "latest" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would fetch latest llama.cpp version from GitHub API"
      llama_version="<latest>"
    else
      info "Resolving latest llama.cpp version..."
      llama_version=$(fetch_latest_version)
      info "Latest version: ${llama_version}"
    fi
  else
    if [[ "$dry_run" == "false" ]]; then
      verify_version_exists "$llama_version"
    fi
  fi

  # --- resolve SM version ---
  if [[ -z "$sm_version" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would auto-detect SM version from local GPU"
      sm_version="<auto>"
    else
      info "Auto-detecting SM version from local GPU..."
      sm_version=$(detect_sm "$gpu_map")
      info "Detected SM: ${sm_version}"
    fi
  else
    # Validate user-provided SM version (always validate, even in dry-run)
    if ! validate_sm "$sm_version" "$gpu_map"; then
      error "Invalid SM version: ${sm_version}\n  → Valid SM versions: $(jq -r '.gpu_families | to_entries[] | .value.sm' "$gpu_map" | sort -n | paste -sd, -)\n  → Run ./scripts/detect.sh to see your GPU's SM version"
    fi
  fi

  # --- resolve CUDA version ---
  if [[ -z "$cuda_version" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      info "[dry-run] Would auto-detect CUDA version from nvcc"
      cuda_version="<auto>"
    else
      cuda_version=$(detect_cuda_version)
      if [[ -z "$cuda_version" ]]; then
        error "Could not detect CUDA version. Install nvcc or use --cuda to specify it."
      fi
      info "Detected CUDA: ${cuda_version}"
    fi
  fi

  # --- compute output paths ---
  local archive_name="llama-${llama_version}-linux-cuda${cuda_version}-sm${sm_version}-x64.tar.gz"
  local archive_path="${output_dir}/${archive_name}"

  # --- dry-run summary ---
  if [[ "$dry_run" == "true" ]]; then
    echo
    echo -e "${BOLD}[llamaup build — DRY RUN]${RESET}"
    echo
    echo -e "  llama.cpp version : ${llama_version}"
    echo -e "  SM version        : ${sm_version}"
    echo -e "  CUDA version      : ${cuda_version}"
    echo -e "  Source dir        : ${src_dir}"
    echo -e "  Build jobs        : ${build_jobs}"
    echo -e "  Output dir        : ${output_dir}"
    echo -e "  Archive name      : ${archive_name}"
    if [[ "$do_upload" == "true" ]]; then
      echo -e "  Upload to         : ${github_repo}"
    fi
    echo
    echo -e "  Steps that would run:"
    echo -e "    1. Clone/checkout llama.cpp @ ${llama_version} → ${src_dir}"
    echo -e "    2. cmake configure (SM ${sm_version})"
    echo -e "    3. cmake build (-j ${build_jobs})"
    echo -e "    4. cmake install"
    echo -e "    5. Package → ${archive_path}"
    echo -e "    6. SHA256  → ${archive_path}.sha256"
    if [[ "$do_upload" == "true" ]]; then
      echo -e "    7. Upload to GitHub Release ${llama_version} on ${github_repo}"
    fi
    echo
    exit 0
  fi

  # --- idempotency check: skip build if valid archive already exists ---
  if [[ -f "$archive_path" ]]; then
    info "Archive already exists: ${archive_path}"
    info "Verifying integrity..."
    
    if verify_archive "$archive_path"; then
      success "Archive is valid — skipping build."
      if [[ "$do_upload" == "true" ]]; then
        upload_release "$archive_path" "$llama_version" "$github_repo"
      fi
      exit 0
    else
      warn "Archive verification failed — removing corrupt file and rebuilding..."
      rm -f "$archive_path" "${archive_path}.sha256"
    fi
  fi

  # --- full build pipeline ---
  local install_dir="/tmp/llamaup-install-sm${sm_version}"

  prepare_source "$llama_version" "$src_dir"
  build "$src_dir" "$sm_version" "$build_jobs" "$install_dir"

  # Set cleanup variable for trap handler
  CLEANUP_ARCHIVE="$archive_path"
  
  local created_archive
  created_archive=$(package "$install_dir" "$sm_version" "$llama_version" "$cuda_version" "$output_dir")
  
  # Clear cleanup variable after successful package
  CLEANUP_ARCHIVE=""

  if [[ "$do_upload" == "true" ]]; then
    upload_release "$created_archive" "$llama_version" "$github_repo"
  fi

  echo
  success "Done! Binary: ${created_archive}"
}

main "$@"