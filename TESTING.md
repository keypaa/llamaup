# Testing Guide

This document describes the testing strategy, available test suites, and how to validate changes before submitting a PR.

---

## Testing Philosophy

The **llamaup** project prioritizes reliability through:

1. **Automated unit tests** for critical functions (GPU matching, archive verification)
2. **Manual integration tests** on real hardware before releases
3. **CI smoke tests** that verify binaries actually run
4. **Shellcheck linting** to catch common bash errors

Every script is designed to **fail loudly** with clear error messages rather than silently producing wrong results.

---

## Automated Test Suites

### `test_task7.sh` — llama-models Minimal Mode

**Purpose:** Validate the minimal mode implementation (Task 7)

**What it tests:**
- Bash syntax validation
- HuggingFace API search functionality
- Model metadata parsing
- GGUF file extraction from model data
- Size formatting (bytes → GiB/MiB)
- Array population and display logic
- Function completeness (all required functions exist)

**How to run:**
```bash
./test_task7.sh
```

**Expected output:**
```
========================================
Task 7 Test Suite: Minimal Mode
========================================

✓ Test 1: Bash syntax validation
  ✓ No syntax errors detected

✓ Test 2: HuggingFace API search
  ✓ API returned 3 models

✓ Test 3: Model metadata parsing
  ✓ Model ID: TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
  ✓ Downloads: 110593
  ✓ Quant count: 12

✓ Test 4: GGUF file extraction
  ✓ Found 12 GGUF files
  ✓ Example: Q2_K - tinyllama-1.1b-chat-v1.0.Q2_K.gguf

...

✓ All automated tests passed!
```

**Interactive testing:**
```bash
# Test search with specific query
./scripts/llama-models search tinyllama

# Test full interactive mode
./scripts/llama-models

# Test minimal mode explicitly
./scripts/llama-models --mode minimal search qwen
```

---

### `scripts/test_gpu_matching.sh`

**Purpose:** Validate GPU name → SM version mapping logic

**What it tests:**
- Correct SM assignment for known GPU models
- Longest-match algorithm (more specific patterns win)
- Edge cases: similar names, substrings, model suffixes

**How to run:**
```bash
./scripts/test_gpu_matching.sh
```

**Expected output:**
```
Testing GPU matching logic...

✓ NVIDIA GeForce RTX 4090 -> SM 89
✓ NVIDIA GeForce RTX 3090 -> SM 86
✓ Tesla T4 -> SM 75
✓ NVIDIA A100-SXM4-40GB -> SM 80
...

Test Results: 15 passed, 0 failed

Testing longest match priority...
✓ Longest match test: GTX 1650 SUPER correctly matched to SM 75

All tests passed!
```

**When to run:**
- After editing `configs/gpu_map.json`
- Before submitting a PR that adds/changes GPU entries
- After changing the `lookup_sm()` function in `detect.sh`

**How to add new test cases:**

Edit `scripts/test_gpu_matching.sh` and add entries to the `test_cases` array:

```bash
declare -A test_cases=(
  ["NVIDIA GeForce RTX 4090"]="89"
  ["Your New GPU Name"]="expected_sm"
  # ... more cases
)
```

---

### `scripts/test_archive_integrity.sh`

**Purpose:** Validate archive verification logic in `build.sh`

**What it tests:**
- Valid tarballs pass verification
- Empty files are rejected
- Corrupted archives are detected
- SHA256 hash mismatches trigger failures
- Partial downloads fail verification

**How to run:**
```bash
./scripts/test_archive_integrity.sh
```

**Expected output:**
```
Test directory: /tmp/llamaup-integrity-test-12345

Test 1: Valid archive without SHA256 file
→ Creating valid test archive...
✓ Test 1 passed: Valid archive accepted

Test 2: Valid archive with correct SHA256
→ Creating archive with matching SHA256...
✓ Test 2 passed: Valid archive with correct hash accepted

...

──────────────────────────────────────
✓ All 7 tests passed!
```

**When to run:**
- After modifying `verify_archive()` in `build.sh`
- Before submitting a PR that changes build/packaging logic
- After changing SHA256 verification behavior

---

## Manual Testing Workflows

### Testing `detect.sh`

```bash
# 1. Test human-readable output
./scripts/detect.sh

# 2. Test JSON output (must be valid)
./scripts/detect.sh --json | jq .

# 3. Validate GPU map for overlaps
LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh

# 4. Test with custom gpu_map.json path
./scripts/detect.sh --gpu-map /path/to/custom/gpu_map.json
```

**Expected behavior:**
- Shows all detected GPUs with their SM versions
-JSON output parses without errors
- Validation mode warns about pattern overlaps across different SM families
- Unknown GPUs print a warning but don't crash

**Edge cases to test:**
- Machine with no GPU (should exit with clear error)
- Machine with multiple GPUs of different types
- GPU not in `gpu_map.json` (should warn and suggest opening an issue)

---

### Testing `build.sh`

```bash
# 1. Dry run (doesn't actually build)
./scripts/build.sh --dry-run --sm 89 --version b4102

# 2. Build without uploading
./scripts/build.sh --sm 89 --output ./dist

# 3. Verify the produced archive
tar -tzf dist/llama-*-sm89-*.tar.gz
sha256sum -c dist/llama-*-sm89-*.tar.gz.sha256

# 4. Test idempotency (running twice should skip rebuild)
./scripts/build.sh --sm 89
./scripts/build.sh --sm 89  # Should skip

# 5. Test with corrupted existing archive (should rebuild)
echo "corrupt" > dist/llama-*-sm89-*.tar.gz
./scripts/build.sh --sm 89  # Should rebuild
```

**Expected behavior:**
- Dry run prints plan without executing anything
- Build produces `.tar.gz` and `.sha256` files in output dir
- Archive contains `llama-cli`, `llama-server`, `llama-bench` at minimum
- Running twice skips rebuild (idempotent)
- Corrupted archives trigger rebuild

**Edge cases to test:**
- `--sm` not provided and no GPU detected → should error with clear message
- Invalid `--version` tag → should fail with API error
- No `GITHUB_TOKEN` when using `--upload` → should fail fast before building

---

### Testing `pull.sh`

```bash
# 1. List available binaries
./scripts/pull.sh --list --repo keypaa/llamaup

# 2. Dry run (doesn't actually download)
./scripts/pull.sh --dry-run --version b4102

# 3. Pull to custom directory
./scripts/pull.sh --install-dir /tmp/test-install

# 4. Verify installed binaries work
/tmp/test-install/llama-cli --version
/tmp/test-install/llama-server --help

# 5. Test idempotency (running twice should skip re-download)
./scripts/pull.sh --install-dir /tmp/test
./scripts/pull.sh --install-dir /tmp/test  # Should skip

# 6. Force re-download
./scripts/pull.sh --install-dir /tmp/test --force
```

**Expected behavior:**
- List mode shows table of available binaries
- Dry run prints what would happen without downloading
- Downloaded binaries execute and show version info
- Running twice skips re-download unless `--force` is used
- SHA256 verification passes (or fails loudly if mismatch)

**Edge cases to test:**
- No GPU and no `--sm` → should error
- Release not found → should error with suggestion
- No binary for detected SM → should list available SMs and suggest building
- SHA256 mismatch → should delete bad file and error

---

### Testing `verify.sh`

```bash
# 1. Create test files
echo "test content" > test.txt
sha256sum test.txt | awk '{print $1}' > test.txt.sha256

# 2. Test auto-discovery (.sha256 in same dir)
./scripts/verify.sh test.txt

# 3. Test with explicit .sha256 file
./scripts/verify.sh test.txt test.txt.sha256

# 4. Test with raw hash string
./scripts/verify.sh test.txt $(cat test.txt.sha256)

# 5. Test hash mismatch
echo "wrong hash" > test.txt.sha256
./scripts/verify.sh test.txt  # Should fail

# 6. Test with URL (mock with local file:// URL)
./scripts/verify.sh test.txt file://$(pwd)/test.txt.sha256
```

**Expected behavior:**
- Matching hashes → exits 0, prints success
- Mismatched hashes → exits 1, prints both expected and actual
- Missing hash source → exits 1 with clear error
- URL sources are fetched with curl

---

### Testing `list.sh`

```bash
# 1. List latest release
./scripts/list.sh --repo keypaa/llamaup

# 2. List specific version
./scripts/list.sh --version b4102

# 3. List all releases (last 10)
./scripts/list.sh --all

# 4. Filter by SM
./scripts/list.sh --sm 89

# 5. JSON output
./scripts/list.sh --json | jq .
```

**Expected behavior:**
- Table output is readable and formatted
- JSON output is valid
- Filtering works correctly
- Missing release → clear error message

---

### Testing `cleanup.sh`

```bash
# 1. List installed versions (interactive)
./scripts/cleanup.sh

# 2. Dry run (see what would be removed)
./scripts/cleanup.sh --dry-run --keep 2

# 3. Keep N most recent
./scripts/cleanup.sh --keep 1

# 4. Remove all (with confirmation)
./scripts/cleanup.sh --all
```

**Expected behavior:**
- Shows installed versions with sizes
- Dry run mode doesn't delete anything
- `--keep N` preserves N most recent versions
- Prompts for confirmation before deletion
- Removes both versioned directories and wrapper scripts

---

## Linting

All shell scripts **must** pass `shellcheck` with zero warnings:

```bash
# Check all scripts
shellcheck scripts/*.sh

# Check a specific script
shellcheck scripts/detect.sh
```

**Install shellcheck:**
- macOS: `brew install shellcheck`
- Ubuntu/Debian: `apt install shellcheck`
- Or: https://www.shellcheck.net/

**Common shellcheck warnings to fix:**
- `SC2086` — Quote variables to prevent word splitting
- `SC2155` — Declare and assign separately to avoid masking return values
- `SC2164` — Use `cd ... || exit` to handle cd failures
- `SC2034` — Unused variables

---

## CI Testing

The GitHub Actions workflow (`.github/workflows/build.yml`) provides:

### Matrix builds
Builds for all SM versions (75, 80, 86, 89, 90, 100, 101, 120) in parallel using NVIDIA CUDA Docker containers.

### Smoke tests
After each build, a smoke test runs in a `nvidia/cuda:*-runtime` container:
```bash
./llama-cli --version
```
If the binary fails to execute or returns an empty version string, the pipeline fails.

### Release publishing
Only runs if **all** smoke tests pass. Creates a GitHub Release and uploads all binaries with SHA256 files.

### Triggering CI manually

```bash
# Via GitHub CLI
gh workflow run build.yml \
  --field llama_version=b4102 \
  --field sm_versions="89,90" \
  --field force_rebuild=true

# Via web UI
# Go to Actions tab → build.yml → Run workflow
```

---

## Testing on Real Hardware

**Before any release:**

1. Test on at least 2 different GPU types (e.g., RTX 4090 and A100)
2. Run full build → pull → execute cycle
3. Verify all core binaries work: `llama-cli`, `llama-server`, `llama-bench`
4. Test with a real model (e.g., `llama-cli -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M -cnv`)

**Hardware test matrix (ideal):**

| GPU | SM | Test |
|-----|-----|------|
| T4 or RTX 2080 | 75 | `pull.sh` + inference test |
| A100 | 80 | `pull.sh` + inference test |
| RTX 3090 or A6000 | 86 | `pull.sh` + inference test |
| RTX 4090 or L40S | 89 | Full build + pull + test |
| H100 | 90 | `pull.sh` + inference test |
| RTX 5090 | 101 | `pull.sh` + inference test (if available) |

---

## Troubleshooting Failed Tests

### `test_gpu_matching.sh` fails

**Symptom:** A GPU name doesn't match the expected SM version

**Cause:** Either the test case is wrong, or `gpu_map.json` needs updating

**Fix:**
1. Check NVIDIA's official compute capability page: https://developer.nvidia.com/cuda-gpus
2. Update `gpu_map.json` if the SM is wrong
3. Update the test case if the expected SM was wrong

---

### `test_archive_integrity.sh` fails

**Symptom:** A verification test unexpectedly passes or fails

**Cause:** Changes to `verify_archive()` may have broken edge case handling

**Fix:**
1. Review recent changes to `scripts/build.sh` → `verify_archive()`
2. Ensure all three checks still work: file size, tarball validity, SHA256 match
3. Add a new test case if you found a new edge case

---

### CI smoke test fails

**Symptom:** Binary builds successfully but fails to execute in runtime container

**Possible causes:**
- CUDA version mismatch (binary requires newer CUDA than runtime container has)
- Missing shared libraries
- Incorrect SM version in binary name (binary works but has wrong metadata)

**Fix:**
1. Check the CUDA container version in `.github/workflows/build.yml`
2. Verify `CMAKE_CUDA_ARCHITECTURES` matches the SM version
3. Test locally in same container: `docker run --rm nvidia/cuda:12.4-runtime-ubuntu22.04 ./llama-cli --version`

---

## Adding New Tests

### For GPU matching

Edit `scripts/test_gpu_matching.sh` and add to `test_cases`:

```bash
declare -A test_cases=(
  # ... existing cases
  ["Your New GPU Model Name"]="expected_sm"
)
```

### For archive integrity

Edit `scripts/test_archive_integrity.sh` and add a new test function:

```bash
test_your_new_case() {
  info "Test description"
  # Test setup
  # Call verify_archive
  # Assert expected behavior
}
```

Then call it from `main()`.

### For new scripts

Create a new test file `scripts/test_YOUR_FEATURE.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source the script you're testing or define test cases

# Test cases here
# Exit 0 on success, 1 on failure
```

Make it executable: `chmod +x scripts/test_YOUR_FEATURE.sh`

---

## Pre-submission Checklist

Before submitting a PR:

- [ ] All automated tests pass: `./scripts/test_*.sh`
- [ ] `shellcheck scripts/*.sh` returns zero warnings
- [ ] Tested on real hardware (at least one GPU type)
- [ ] Documentation updated (README, CONTRIBUTING, or TESTING)
- [ ] Git commit messages are descriptive
- [ ] No secrets or credentials in code or commit history

---

## Questions?

If you're unsure how to test a particular change, open a draft PR and ask for guidance. The maintainers are happy to help!
