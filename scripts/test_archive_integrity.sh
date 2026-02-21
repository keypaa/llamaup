#!/usr/bin/env bash
# test_archive_integrity.sh — Test archive integrity verification in build.sh
#
# This test suite validates the verify_archive() function that was added to
# build.sh to prevent idempotency issues with corrupt or incomplete archives.
#
# Tests covered:
#   1. Valid archive without .sha256 file (should pass)
#   2. Valid archive with correct SHA256 (should pass)
#   3. Empty archive file (should fail verification)
#   4. Corrupt/invalid tarball (should fail verification)
#   5. SHA256 hash mismatch (should fail verification)
#   6. Wrong SHA256 hash value (should fail verification)
#   7. Partial/truncated download (should fail verification)
#
# Usage: ./scripts/test_archive_integrity.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colour constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Define warn() helper needed by verify_archive
warn() { echo -e "${YELLOW}⚠ $1${RESET}" >&2; }

# ---------------------------------------------------------------------------
# verify_archive — verify that an archive is valid and matches its SHA256
# (Extracted from build.sh for testing)
# Args: $1 = archive_path (path to .tar.gz file)
# Returns: 0 if valid, 1 if invalid or corrupt
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
# Test output helpers
# ---------------------------------------------------------------------------

info()    { echo -e "${CYAN}→ $1${RESET}"; }
success() { echo -e "${GREEN}✓ $1${RESET}"; }
fail()    { echo -e "${RED}✗ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}" >&2; }

TEST_DIR="/tmp/llamaup-integrity-test-$$"
PASSED=0
FAILED=0

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
setup() {
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  info "Test directory: $TEST_DIR"
}

cleanup() {
  cd /
  rm -rf "$TEST_DIR"
  echo
  echo "──────────────────────────────────────"
  if [[ $FAILED -eq 0 ]]; then
    success "All $PASSED tests passed!"
    return 0
  else
    fail "$FAILED test(s) failed, $PASSED passed"
    return 1
  fi
}

# No trap - we'll call cleanup explicitly at the end of main

run_test() {
  local test_name="$1"
  local test_fn="$2"
  
  echo
  info "Test: $test_name"
  
  # Temporarily disable exit on error for test function execution
  set +e
  $test_fn
  local result=$?
  set -e
  
  if [[ $result -eq 0 ]]; then
    success "PASS: $test_name"
    PASSED=$((PASSED + 1))
  else
    fail "FAIL: $test_name"
    FAILED=$((FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test_valid_archive_no_sha256() {
  local archive="valid-no-sha.tar.gz"
  
  # Create a valid tarball
  mkdir -p test-content
  echo "test data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Should pass (no .sha256 file to verify against)
  verify_archive "$archive"
  local result=$?
  
  rm -rf test-content "$archive"
  return $result
}

test_valid_archive_with_correct_sha256() {
  local archive="valid-with-sha.tar.gz"
  
  # Create a valid tarball
  mkdir -p test-content
  echo "test data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Generate correct SHA256
  sha256sum "$archive" | awk '{print $1}' > "${archive}.sha256"
  
  # Should pass
  verify_archive "$archive"
  local result=$?
  
  rm -rf test-content "$archive" "${archive}.sha256"
  return $result
}

test_empty_archive() {
  local archive="empty.tar.gz"
  
  # Create empty file
  touch "$archive"
  
  # Should fail (empty file)
  if verify_archive "$archive"; then
    echo "ERROR: Empty archive passed verification!" >&2
    rm "$archive"
    return 1
  fi
  
  rm "$archive"
  return 0
}

test_corrupt_tarball() {
  local archive="corrupt.tar.gz"
  
  # Create a file that's not a valid tarball
  echo "this is not a tarball" > "$archive"
  
  # Should fail (not a valid tar)
  if verify_archive "$archive"; then
    echo "ERROR: Corrupt tarball passed verification!" >&2
    rm "$archive"
    return 1
  fi
  
  rm "$archive"
  return 0
}

test_sha256_mismatch() {
  local archive="sha-mismatch.tar.gz"
  
  # Create a valid tarball
  mkdir -p test-content
  echo "original data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Generate SHA256
  sha256sum "$archive" | awk '{print $1}' > "${archive}.sha256"
  
  # Modify the archive (invalidate the hash)
  rm -rf test-content
  mkdir -p test-content
  echo "modified data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Should fail (hash mismatch)
  if verify_archive "$archive"; then
    echo "ERROR: Archive with hash mismatch passed verification!" >&2
    rm -rf test-content "$archive" "${archive}.sha256"
    return 1
  fi
  
  rm -rf test-content "$archive" "${archive}.sha256"
  return 0
}

test_wrong_sha256_format() {
  local archive="wrong-format.tar.gz"
  
  # Create a valid tarball
  mkdir -p test-content
  echo "test data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Create .sha256 with wrong hash
  echo "0000000000000000000000000000000000000000000000000000000000000000" > "${archive}.sha256"
  
  # Should fail (hash mismatch)
  if verify_archive "$archive"; then
    echo "ERROR: Archive with wrong hash passed verification!" >&2
    rm -rf test-content "$archive" "${archive}.sha256"
    return 1
  fi
  
  rm -rf test-content "$archive" "${archive}.sha256"
  return 0
}

test_partial_download() {
  local archive="partial.tar.gz"
  
  # Create a valid tarball first
  mkdir -p test-content
  echo "test data" > test-content/file.txt
  tar -czf "$archive" test-content
  
  # Truncate it (simulate interrupted download)
  truncate -s 100 "$archive"
  
  # Should fail (corrupt tarball)
  if verify_archive "$archive"; then
    echo "ERROR: Partial/truncated archive passed verification!" >&2
    rm -rf test-content "$archive"
    return 1
  fi
  
  rm -rf test-content "$archive"
  return 0
}

# ---------------------------------------------------------------------------
# Main test runner
# ---------------------------------------------------------------------------
main() {
  echo "════════════════════════════════════════"
  echo "  Archive Integrity Verification Tests"
  echo "════════════════════════════════════════"
  
  setup
  
  run_test "Valid archive without .sha256 file" test_valid_archive_no_sha256
  run_test "Valid archive with correct SHA256" test_valid_archive_with_correct_sha256
  run_test "Empty archive file" test_empty_archive
  run_test "Corrupt/invalid tarball" test_corrupt_tarball
  run_test "SHA256 hash mismatch" test_sha256_mismatch
  run_test "Wrong SHA256 hash value" test_wrong_sha256_format
  run_test "Partial/truncated download" test_partial_download
  
  # Clean up and exit
  cleanup
  exit $?
}

main "$@"
