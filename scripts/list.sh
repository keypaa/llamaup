#!/usr/bin/env bash
# list.sh — Query GitHub Releases and display available llamaup binaries
# in a clean, filterable table.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

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
Usage: list.sh [OPTIONS]

Query GitHub Releases and display available pre-built llama.cpp binaries.

Options:
  --repo <owner/repo>   GitHub repo to query. Overrides LLAMA_DEPLOY_REPO.
  --version <tag>       Show only this version. Default: latest.
  --all                 Show all available releases (last 10).
  --sm <version>        Filter by SM version (e.g. --sm 89).
  --json                Output as JSON.
  -h, --help            Show this help.

Environment variables:
  LLAMA_DEPLOY_REPO     GitHub repo to query

Examples:
  ./scripts/list.sh --repo my-org/llamaup
  ./scripts/list.sh --repo my-org/llamaup --version b4200
  ./scripts/list.sh --repo my-org/llamaup --all
  ./scripts/list.sh --repo my-org/llamaup --sm 89
  ./scripts/list.sh --repo my-org/llamaup --json
EOF
  exit 0
}

error()   { echo -e "${RED}Error: $1${RESET}" >&2; exit 1; }
info()    { echo -e "${CYAN}→ $1${RESET}"; }

# ---------------------------------------------------------------------------
# fetch_releases — fetch one or many releases from GitHub API
# Args:
#   $1 = github_repo (e.g. "my-org/llamaup")
#   $2 = version ("latest", "all", or a specific tag like "b4200")
# Returns: JSON array of release objects on stdout
# Exits 1 on API failure or release not found.
# ---------------------------------------------------------------------------
fetch_releases() {
  local github_repo="$1"
  local version="$2"
  local url response

  if [[ "$version" == "all" ]]; then
    url="https://api.github.com/repos/${github_repo}/releases?per_page=10"
    response=$(curl -fsSL "$url" 2>/dev/null) || {
      error "Failed to fetch releases from:\n  ${url}\n  → Check your internet connection."
    }
    # API returns a JSON array directly for the list endpoint
    echo "$response"
  elif [[ "$version" == "latest" ]]; then
    url="https://api.github.com/repos/${github_repo}/releases/latest"
    response=$(curl -fsSL "$url" 2>/dev/null) || {
      error "Failed to fetch latest release from:\n  ${url}"
    }
    if echo "$response" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
      error "No releases found for ${github_repo}.\n  → Check the repo name with --repo."
    fi
    # Wrap single release in an array for uniform handling
    echo "[$response]"
  else
    url="https://api.github.com/repos/${github_repo}/releases/tags/${version}"
    response=$(curl -fsSL "$url" 2>/dev/null) || {
      error "Failed to fetch release '${version}' from:\n  ${url}"
    }
    if echo "$response" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
      error "Release '${version}' not found on ${github_repo}.\n  → Run with --all to see available releases."
    fi
    echo "[$response]"
  fi
}

# ---------------------------------------------------------------------------
# parse_asset_fields — extract structured fields from a binary asset name
# Asset naming: llama-{version}-linux-cuda{cuda}-sm{sm}-x64.tar.gz
# Args: $1 = asset_name
# Returns: "version|sm|cuda" or empty if the name doesn't match the pattern
# ---------------------------------------------------------------------------
parse_asset_fields() {
  local name="$1"

  # Use bash regex to extract fields from the naming convention
  # Pattern: llama-{version}-linux-cuda{cuda}-sm{sm}-x64.tar.gz
  if [[ "$name" =~ llama-([^-]+)-linux-cuda([^-]+)-sm([0-9]+)-x64\.tar\.gz ]]; then
    local ver="${BASH_REMATCH[1]}"
    local cuda="${BASH_REMATCH[2]}"
    local sm="${BASH_REMATCH[3]}"
    echo "${ver}|${sm}|${cuda}"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# print_release_table — format and print release assets as a readable table
# Args:
#   $1 = releases_json (JSON array of release objects)
#   $2 = sm_filter (optional — only show rows matching this SM, or "" for all)
# ---------------------------------------------------------------------------
print_release_table() {
  local releases_json="$1"
  local sm_filter="$2"

  # Collect all non-.sha256 assets across all releases into a flat list
  # Each line: "release_tag|asset_name|size_bytes|published_at"
  local assets_data
  assets_data=$(echo "$releases_json" | jq -r '
    .[] |
    .tag_name as $tag |
    .published_at as $pub |
    .assets[] |
    select(.name | endswith(".sha256") | not) |
    "\($tag)|\(.name)|\(.size)|\($pub)"
  ')

  if [[ -z "$assets_data" ]]; then
    echo -e "${YELLOW}No binaries found.${RESET}"
    return 0
  fi

  # Determine the version label for the header (use first release's tag)
  local first_tag
  first_tag=$(echo "$releases_json" | jq -r '.[0].tag_name')
  local repo_display
  repo_display=$(echo "$releases_json" | jq -r '.[0].html_url // ""' \
    | grep -oP 'github\.com/\K[^/]+/[^/]+' || echo "llamaup")

  echo
  echo -e "${BOLD}Available binaries — ${repo_display} / ${first_tag}${RESET}"
  echo

  # Print the header
  printf "  %-10s  %-4s  %-24s  %-8s  %-8s  %-19s\n" \
    "Version" "SM" "Architecture" "CUDA" "Size" "Published"
  printf "  %-10s  %-4s  %-24s  %-8s  %-8s  %-19s\n" \
    "-------" "----" "------------------------" "------" "-------" "-------------------"

  local gpu_map="${SCRIPT_DIR}/../configs/gpu_map.json"

  while IFS='|' read -r rel_tag asset_name size_bytes published_at; do
    local fields
    fields=$(parse_asset_fields "$asset_name")
    [[ -z "$fields" ]] && continue

    local ver sm cuda
    IFS='|' read -r ver sm cuda <<< "$fields"

    # Apply SM filter if set
    if [[ -n "$sm_filter" && "$sm" != "$sm_filter" ]]; then
      continue
    fi

    # Look up architecture name from gpu_map if available
    local arch="unknown"
    if [[ -f "$gpu_map" ]]; then
      arch=$(jq -r --arg sm "$sm" \
        '.gpu_families | to_entries[] | select(.value.sm == $sm) | .value.architecture' \
        "$gpu_map" 2>/dev/null || echo "unknown")
      [[ -z "$arch" || "$arch" == "null" ]] && arch="unknown"
    fi

    # Format size as MB
    local size_mb
    size_mb=$(awk "BEGIN {printf \"%.0f MB\", ${size_bytes}/1048576}")

    # Format date: 2025-03-01T14:22:00Z → 2025-03-01 14:22 UTC
    local date_display
    date_display=$(echo "$published_at" | sed 's/T/ /; s/:[0-9][0-9]Z$/ UTC/')

    printf "  %-10s  %-4s  %-24s  %-8s  %-8s  %-19s\n" \
      "$ver" "$sm" "$arch" "$cuda" "$size_mb" "$date_display"

  done <<< "$assets_data"

  echo
  echo -e "  Download: ${CYAN}./scripts/pull.sh --version ${first_tag} [--sm <sm>]${RESET}"
  echo
}

# ---------------------------------------------------------------------------
# print_json — output all assets as a JSON array
# Args:
#   $1 = releases_json (JSON array of release objects)
#   $2 = sm_filter (optional)
# ---------------------------------------------------------------------------
print_json() {
  local releases_json="$1"
  local sm_filter="$2"

  echo "$releases_json" | jq --arg sm_filter "$sm_filter" '
    [ .[] |
      .tag_name as $tag |
      .published_at as $pub |
      .assets[] |
      select(.name | endswith(".sha256") | not) |
      {
        version: $tag,
        name: .name,
        url: .browser_download_url,
        size: .size,
        published: $pub
      }
    ] |
    if $sm_filter != "" then
      map(select(.name | contains("sm" + $sm_filter)))
    else . end
  '
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local github_repo="${LLAMA_DEPLOY_REPO:-}"
  local version="latest"
  local sm_filter=""
  local output_json=false
  local fetch_all=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)    github_repo="$2" ; shift 2 ;;
      --version) version="$2"     ; shift 2 ;;
      --all)     fetch_all=true   ; shift ;;
      --sm)      sm_filter="$2"   ; shift 2 ;;
      --json)    output_json=true ; shift ;;
      -h|--help) usage ;;
      *)         error "Unknown option: $1. Run with --help for usage." ;;
    esac
  done

  # --- require repo before any network calls ---
  if [[ -z "$github_repo" ]]; then
    error "No GitHub repo specified.\n  → Use --repo owner/repo or set LLAMA_DEPLOY_REPO."
  fi

  if [[ "$fetch_all" == "true" ]]; then
    version="all"
  fi

  info "Fetching releases from ${github_repo}..."
  local releases_json
  releases_json=$(fetch_releases "$github_repo" "$version")

  if [[ "$output_json" == "true" ]]; then
    print_json "$releases_json" "$sm_filter"
  else
    print_release_table "$releases_json" "$sm_filter"
  fi
}

main "$@"