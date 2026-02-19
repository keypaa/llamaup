# Contributing to llamaup

Thank you for helping make llamaup better! This guide covers the three main ways
to contribute:

1. Fix or add a GPU mapping in `gpu_map.json`
2. Contribute a pre-built binary for a new SM version
3. Report a broken or missing binary
4. Contribute code to the scripts

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
   - More specific names should come first within a family (e.g. `"RTX 3080 Ti"` before `"RTX 3080"`)

### Verify before submitting

```bash
# 1. Check that the JSON is still valid
jq . configs/gpu_map.json

# 2. Run detect.sh before and after your change
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
git clone https://github.com/your-org/llamaup.git
cd llamaup

# 2. Build for your SM version and upload to the project's releases
./scripts/build.sh --sm <your-sm> --upload --repo your-org/llamaup
```

For example, for a Hopper H100 (SM 90):

```bash
./scripts/build.sh --sm 90 --upload --repo your-org/llamaup
```

### Verify the upload worked

```bash
./scripts/list.sh --repo your-org/llamaup
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
