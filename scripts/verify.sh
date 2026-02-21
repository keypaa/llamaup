#!/usr/bin/env bash
# verify.sh — Standalone SHA256 checksum verifier for a locally downloaded binary.
# The hash source can be a local .sha256 file, a URL, or a raw 64-char hex string.
set -euo pipefail

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
Usage: verify.sh <file> [<sha256-source>]

Verify a local file against its SHA256 checksum.
Always prints both the expected and actual hash.

Arguments:
  file              Path to the file to verify.
  sha256-source     One of:
                      - Path to a local .sha256 file
                      - A URL pointing to a .sha256 file
                      - A raw 64-character SHA256 hex string
                    If omitted, looks for <file>.sha256 in the same directory.

Options:
  -h, --help        Show this help.

Examples:
  ./scripts/verify.sh llama-b4200-linux-cuda12.4-sm89-x64.tar.gz
  ./scripts/verify.sh archive.tar.gz archive.tar.gz.sha256
  ./scripts/verify.sh archive.tar.gz https://example.com/archive.tar.gz.sha256
  ./scripts/verify.sh archive.tar.gz a3f1c2...(64 hex chars)
EOF
  exit 0
}

error()   { echo -e "${RED}Error: $1${RESET}" >&2; exit 1; }
info()    { echo -e "${CYAN}→ $1${RESET}"; }
success() { echo -e "${GREEN}✓ $1${RESET}"; }

# ---------------------------------------------------------------------------
# resolve_hash — extract the hash from any of the 3 supported source types
# Args:
#   $1 = hash_source (local path, URL, or raw 64-char hex string)
# Returns: the 64-char hex hash on stdout
# Exits 1 if the source cannot be resolved.
# ---------------------------------------------------------------------------
resolve_hash() {
  local hash_source="$1"

  # 1. Raw hex string: exactly 64 hex characters
  if [[ "$hash_source" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "$hash_source"
    return 0
  fi

  # 2. URL: starts with http:// or https://
  if [[ "$hash_source" =~ ^https?:// ]]; then
    local content
    content=$(curl -fsSL "$hash_source" 2>/dev/null) || {
      error "Failed to fetch SHA256 from URL:\n  ${hash_source}"
    }
    echo "$content" | awk '{print $1}'
    return 0
  fi

  # 3. Local file path
  if [[ -f "$hash_source" ]]; then
    awk '{print $1}' "$hash_source"
    return 0
  fi

  error "SHA256 source not found: ${hash_source}\n  → Provide a valid file path, URL, or 64-char hex string."
}

# ---------------------------------------------------------------------------
# verify — verify a file against a hash source, print both hashes
# Args:
#   $1 = file_path
#   $2 = hash_source (path, URL, or raw hex string)
# Returns: 0 on match, exits 1 on mismatch
# ---------------------------------------------------------------------------
verify() {
  local file_path="$1"
  local hash_source="$2"

  if [[ ! -f "$file_path" ]]; then
    error "File not found: ${file_path}"
  fi

  info "Resolving expected hash from: ${hash_source}"
  local expected_hash
  expected_hash=$(resolve_hash "$hash_source")

  if [[ -z "$expected_hash" ]]; then
    error "Could not extract a hash from: ${hash_source}"
  fi

  info "Computing SHA256 of: $(basename "$file_path")..."
  local actual_hash
  actual_hash=$(sha256sum "$file_path" | awk '{print $1}')

  echo
  echo -e "  Expected : ${BOLD}${expected_hash}${RESET}"
  echo -e "  Actual   : ${BOLD}${actual_hash}${RESET}"
  echo

  if [[ "$expected_hash" == "$actual_hash" ]]; then
    success "SHA256 match — file is intact. ✓"
    return 0
  else
    echo -e "${RED}SHA256 MISMATCH — file may be corrupt or tampered with.${RESET}" >&2
    echo "  → Delete the file and re-download." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local file_path=""
  local hash_source=""

  # Handle --help before positional arg parsing
  for arg in "$@"; do
    case "$arg" in
      -h|--help) usage ;;
    esac
  done

  if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: no file specified.${RESET}" >&2
    echo "  → Run: verify.sh --help" >&2
    exit 1
  fi

  file_path="$1"

  if [[ $# -ge 2 ]]; then
    hash_source="$2"
  else
    # Auto-discover: look for <file>.sha256 in the same directory
    local auto_sha256="${file_path}.sha256"
    if [[ ! -f "$auto_sha256" ]]; then
      error "No SHA256 source provided and no auto-discovered file at:\n  ${auto_sha256}\n  → Provide a sha256 source as the second argument."
    fi
    info "Auto-discovered checksum file: ${auto_sha256}"
    hash_source="$auto_sha256"
  fi

  verify "$file_path" "$hash_source"
}

main "$@"