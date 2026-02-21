# Contributing to llamaup

Thank you for helping make llamaup better! This guide covers the main ways
to contribute:

1. Fix or add a GPU mapping in `gpu_map.json`
2. Contribute a pre-built binary for a new SM version
3. Report a broken or missing binary
4. Contribute code to the scripts
5. Testing and validation

**Additional resources:**
- [TESTING.md](TESTING.md) — Detailed testing guide and manual test workflows
- [GPU_MATCHING.md](docs/GPU_MATCHING.md) — How GPU substring matching works
- [README.md](README.md) — Main documentation and scripts reference

---

## 1. How to add or fix a GPU mapping

The single source of truth for GPU → SM version mappings is
[`configs/gpu_map.json`](configs/gpu_map.json).

### Find the correct SM version

Look up the correct Compute Capability (SM version) for your GPU on NVIDIA's
official page:

> **https://developer.nvidia.com/cuda-gpus**

The "Compute Capability" column maps directly to the SM version used here
(e.g. Compute Capability 8.9 = `sm_89`).

### Make the change

1. Open `configs/gpu_map.json`
2. Find the correct `sm_XX` family (or add a new one if the architecture is new)
3. Add the GPU model name string to the `gpus` array
   - Use the substring that `nvidia-smi` reports (run `nvidia-smi --query-gpu=name --format=csv,noheader` to see yours)
   - **Pattern specificity**: More specific patterns are better (e.g., `"RTX 6000 Ada"` instead of just `"RTX 6000"`)
   - **Order doesn't matter**: The matching logic uses "longest match", so the most specific pattern will always win
   
See [docs/GPU_MATCHING.md](docs/GPU_MATCHING.md) for details on how substring matching works.

### Verify before submitting

```bash
# 1. Check that the JSON is still valid
jq . configs/gpu_map.json

# 2. Validate for pattern overlaps (optional but recommended)
LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh

# 3. Run detect.sh to confirm your GPU is correctly identified
./scripts/detect.sh
```

### PR checklist

- [ ] `jq . configs/gpu_map.json` exits 0
- [ ] `./scripts/detect.sh` correctly identifies your GPU with the new/fixed mapping
- [ ] The GPU name substring matches what `nvidia-smi` reports
- [ ] You linked to a source (NVIDIA's page or official spec) in the PR description

---

## 2. How to contribute a binary for a new SM version

If you have access to a GPU with an SM version not yet covered, you can build
and upload a binary.

### Prerequisites

- NVIDIA GPU with the target SM version
- CUDA toolkit installed (`nvcc` available in PATH)
- `cmake` ≥ 3.24
- `ninja`
- `gh` CLI authenticated (`gh auth login`)

### Steps

```bash
# 1. Clone llamaup
git clone https://github.com/keypaa/llamaup.git
cd llamaup

# 2. Build for your SM version and upload to the project's releases
./scripts/build.sh --sm <your-sm> --upload --repo keypaa/llamaup
```

For example, for a Hopper H100 (SM 90):

```bash
./scripts/build.sh --sm 90 --upload --repo keypaa/llamaup
```

### Verify the upload worked

```bash
./scripts/list.sh --repo keypaa/llamaup
```

Your new binary should appear in the table.

---

## 3. How to report a bad or missing binary

If a downloaded binary crashes, fails to run, or the wrong binary was selected
for your GPU, please open a GitHub issue using the appropriate template:

- **Wrong GPU/SM mapping** → [wrong_sm issue template](.github/ISSUE_TEMPLATE/wrong_sm.md)
- **Binary doesn't work** → [bad_binary issue template](.github/ISSUE_TEMPLATE/bad_binary.md)

### What to include

Always attach the output of:

```bash
./scripts/detect.sh --json
```

This gives maintainers all the GPU, SM, CUDA, and driver info needed to
reproduce and diagnose the issue.

---

## 4. Code contribution guidelines

### Linting

All shell scripts must pass `shellcheck` with zero warnings:

```bash
shellcheck scripts/*.sh
```

Install shellcheck: https://www.shellcheck.net/

### Testing

- Test on at least one real GPU before submitting a PR
- Run `./scripts/detect.sh` to verify GPU detection works
- For build changes, run `./scripts/build.sh --dry-run --sm 89 --version b4200`

### Style rules

- Every script starts with `set -euo pipefail`
- All functions have a comment block (purpose, args, return value)
- Variables are always `local` inside functions — declared before assignment
- Colour constants: `RED GREEN YELLOW CYAN BOLD RESET`
- No Python, no Node — keep scripts dependency-minimal
- No hardcoded paths — use variables with overridable defaults
- Every error message must suggest a corrective action

### Adding a new script

If you add a new script, source `detect.sh` for any GPU/SM detection logic
rather than duplicating it:

```bash
source "${SCRIPT_DIR}/detect.sh"
```

Ensure the new script:
- Resolves its own path with `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- Supports `-h` / `--help` (exits 0)
- Passes `shellcheck` with no warnings
---

## 5. Testing

### Test scripts

The project includes automated test suites to verify critical functionality:

#### `scripts/test_gpu_matching.sh` — GPU matching logic tests

Validates that GPU names are correctly mapped to SM versions using the longest-match algorithm.

```bash
./scripts/test_gpu_matching.sh
```

**What it tests:**
- Correct SM mapping for various GPU models (RTX 4090, A100, T4, H100, etc.)
- Longest-match priority (e.g., "GTX 1650 Super" wins over "GTX 1650")
- Pattern overlap detection across SM families

**When to run:**
- After modifying `configs/gpu_map.json`
- Before submitting a PR that changes GPU detection logic
- To verify a new GPU addition works correctly

#### `scripts/test_archive_integrity.sh` — Archive verification tests

Tests the archive integrity verification logic in `build.sh` to prevent issues with corrupt or incomplete downloads.

```bash
./scripts/test_archive_integrity.sh
```

**What it tests:**
- Valid archives pass verification
- Empty files are rejected
- Corrupted tarballs are detected
- SHA256 hash mismatches are caught
- Partial/truncated downloads fail verification

**When to run:**
- After modifying the `verify_archive()` function in `build.sh`
- Before submitting a PR that changes build or verification logic
- To validate checksum handling

### Manual testing checklist

Before submitting a PR, especially for core script changes:

**For `detect.sh` changes:**
- [ ] Run on a machine with a real GPU
- [ ] Verify `--json` output is valid JSON (`./scripts/detect.sh --json | jq .`)
- [ ] Test with `LLAMA_VALIDATE_GPU_MAP=1` to check for pattern overlaps

**For `build.sh` changes:**
- [ ] Run `--dry-run` and verify output is sensible
- [ ] Test a real build with `--sm <your-sm>`
- [ ] Verify the produced tarball is valid: `tar -tzf dist/*.tar.gz`
- [ ] Check that `.sha256` file is created alongside the tarball

**For `pull.sh` changes:**
- [ ] Test `--dry-run` mode
- [ ] Test `--list` mode
- [ ] Test actual download and installation
- [ ] Verify installed binaries work: `~/.local/bin/llama/llama-cli --version`

**For `gpu_map.json` changes:**
- [ ] Validate JSON: `jq . configs/gpu_map.json`
- [ ] Run GPU matching tests: `./scripts/test_gpu_matching.sh`
- [ ] Run detect.sh with validation: `LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh`

### Continuous Integration

The GitHub Actions workflow (`.github/workflows/build.yml`) runs automatically on:
- New llama.cpp releases (daily check)
- Manual workflow dispatch
- Repository dispatch events

The CI pipeline:
1. Builds binaries for all SM versions in parallel
2. Runs smoke tests (verifies each binary executes)
3. Creates a GitHub Release with all binaries attached

To test workflow changes locally, use `act` or validate the YAML syntax:

```bash
# Install act (GitHub Actions local runner)
# https://github.com/nektos/act

# Dry run the workflow
act workflow_dispatch --dryrun
```

---

**For more detailed testing information**, see [TESTING.md](TESTING.md), which includes:
- Complete manual testing workflows for each script
- How to add new test cases
- Troubleshooting failed tests
- Pre-submission checklist
