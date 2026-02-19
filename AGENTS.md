# AGENTS.md — Full Implementation Spec

This document is the authoritative task list for implementing `llamaup`.
Read `CLAUDE.md` first for project context, conventions, and design decisions.
Execute tasks in order. Each task has a clear acceptance criteria — do not move
to the next task until all criteria for the current one pass.

---

## TASK 0 — Repo bootstrap

**Goal:** Ensure the folder and file structure is correct before writing any code.

### Actions
Create the following empty files and directories if they don't already exist:

```
scripts/build.sh
scripts/pull.sh
scripts/detect.sh
scripts/verify.sh
scripts/list.sh
configs/gpu_map.json
.github/workflows/build.yml
.github/ISSUE_TEMPLATE/wrong_sm.md
.github/ISSUE_TEMPLATE/bad_binary.md
CONTRIBUTING.md
README.md
LICENSE
```

Make all `.sh` files executable: `chmod +x scripts/*.sh`

### Acceptance criteria
- [ ] `ls scripts/` shows all 5 scripts
- [ ] `ls configs/` shows `gpu_map.json`
- [ ] `ls .github/workflows/` shows `build.yml`
- [ ] All `.sh` files have execute permission

---

## TASK 1 — `configs/gpu_map.json`

**Goal:** A complete, accurate JSON lookup table mapping GPU model name substrings
to SM versions. This is the single source of truth for all scripts.

### Exact schema

```json
{
  "_comment": "Maps GPU model name substrings (from nvidia-smi) to CUDA SM versions.",
  "_note": "Matching is case-insensitive substring search. Order matters — more specific entries should come first within a family.",
  "gpu_families": {
    "sm_75": {
      "sm": "75",
      "cuda_min": "11.0",
      "architecture": "Turing",
      "gpus": ["T4", "RTX 2060", "RTX 2070", "RTX 2080", "Quadro RTX 3000", "Quadro RTX 4000", "Quadro RTX 5000", "Quadro RTX 6000", "Quadro RTX 8000", "GTX 1650 Super", "GTX 1660"]
    },
    "sm_80": {
      "sm": "80",
      "cuda_min": "11.0",
      "architecture": "Ampere HPC",
      "gpus": ["A100", "A30"]
    },
    "sm_86": {
      "sm": "86",
      "cuda_min": "11.1",
      "architecture": "Ampere Consumer",
      "gpus": ["RTX 3050", "RTX 3060", "RTX 3070", "RTX 3080", "RTX 3090", "A10", "A40", "RTX A2000", "RTX A4000", "RTX A5000", "RTX A6000"]
    },
    "sm_89": {
      "sm": "89",
      "cuda_min": "11.8",
      "architecture": "Ada Lovelace",
      "gpus": ["RTX 4050", "RTX 4060", "RTX 4070", "RTX 4080", "RTX 4090", "L4", "L40S", "L40", "RTX 6000 Ada", "RTX 5000 Ada", "RTX 4500 Ada", "RTX 4000 Ada", "RTX 2000 Ada"]
    },
    "sm_90": {
      "sm": "90",
      "cuda_min": "11.8",
      "architecture": "Hopper",
      "gpus": ["H100", "H200", "GH200"]
    },
    "sm_100": {
      "sm": "100",
      "cuda_min": "12.8",
      "architecture": "Blackwell Datacenter",
      "gpus": ["B100", "B200", "GB200"]
    },
    "sm_101": {
      "sm": "101",
      "cuda_min": "12.8",
      "architecture": "Blackwell Consumer",
      "gpus": ["RTX 5050", "RTX 5060", "RTX 5070", "RTX 5080", "RTX 5090"]
    },
    "sm_120": {
      "sm": "120",
      "cuda_min": "12.8",
      "architecture": "Blackwell Workstation",
      "gpus": ["RTX PRO 6000 Blackwell", "RTX PRO 5000 Blackwell", "RTX PRO 4500 Blackwell", "RTX PRO 4000 Blackwell", "RTX PRO 2000 Blackwell"]
    }
  }
}
```

### Acceptance criteria
- [ ] `jq . configs/gpu_map.json` exits 0 (valid JSON)
- [ ] Every family has `sm`, `cuda_min`, `architecture`, and `gpus` keys
- [ ] `jq '.gpu_families | keys' configs/gpu_map.json` returns all 8 SM families
- [ ] sm_120 and sm_101 are separate entries (Blackwell split is correct)

---

## TASK 2 — `scripts/detect.sh`

**Goal:** A standalone diagnostic script that reports everything about the local
GPU environment. Used by users to debug issues and by other scripts internally.

### Function signatures

```bash
# Print usage and exit 0
usage()

# Check that nvidia-smi and jq are available. Exit 1 with clear message if not.
# Args: none
# Returns: nothing (exits on failure)
check_deps()

# Query nvidia-smi for all connected GPUs.
# Returns: newline-separated list of GPU names (one per GPU)
# Exit 1 if nvidia-smi not found or returns no output.
get_gpu_names()

# Given a GPU name string, look up its SM version in gpu_map.json.
# Uses case-insensitive substring matching with jq.
# Args: $1 = gpu_name (string), $2 = path to gpu_map.json
# Returns: SM version string (e.g. "89"), or empty string if not found
# Does NOT exit on no match — caller decides what to do
lookup_sm()  

# Detect the installed CUDA toolkit version via nvcc.
# Returns: version string like "12.4", or empty string if nvcc not found
detect_cuda_version()

# Detect the NVIDIA driver version via nvidia-smi.
# Returns: version string like "535.104.05", or empty string on failure
detect_driver_version()

# Main entrypoint. Prints a formatted report:
#   GPU(s) found, SM version for each, CUDA toolkit version, driver version.
#   If SM not found in gpu_map.json, prints a warning with instructions.
# Args: [--json] to output as JSON instead of human-readable
main()
```

### CLI interface

```
Usage: detect.sh [OPTIONS]

Options:
  --json        Output as JSON instead of human-readable text
  --gpu-map     Path to gpu_map.json (default: ../configs/gpu_map.json relative to script)
  -h, --help    Show this help
```

### Expected human-readable output (example)

```
[llamaup detect]

GPU 0:  NVIDIA L40S
  SM version : 89  (Ada Lovelace)
  CUDA min   : 11.8

GPU 1:  NVIDIA T4
  SM version : 75  (Turing)
  CUDA min   : 11.0

CUDA toolkit : 12.4  (nvcc)
Driver       : 535.104.05

All GPUs have known SM versions. ✓
```

### Expected JSON output (example)

```json
{
  "gpus": [
    { "name": "NVIDIA L40S", "sm": "89", "architecture": "Ada Lovelace", "cuda_min": "11.8" },
    { "name": "NVIDIA T4",   "sm": "75", "architecture": "Turing",        "cuda_min": "11.0" }
  ],
  "cuda_toolkit": "12.4",
  "driver": "535.104.05"
}
```

### Edge cases to handle
- No GPU found → print clear error, suggest checking `nvidia-smi` manually, exit 1
- GPU found but SM not in gpu_map.json → print warning, show GPU name, suggest opening an issue, exit 0 (not a fatal error)
- Multiple GPUs → report all of them
- nvcc not found → report CUDA as "not found", still report GPU info
- `--gpu-map` path doesn't exist → exit 1 with clear error

### Acceptance criteria
- [ ] `./scripts/detect.sh --help` prints usage and exits 0
- [ ] `./scripts/detect.sh --json` outputs valid JSON (pipe to `jq .`)
- [ ] `./scripts/detect.sh` with no GPU prints a clear error and exits 1
- [ ] Unknown GPU prints a warning but exits 0
- [ ] Script works when called from any working directory (uses path relative to `$0`)

---

## TASK 3 — `scripts/build.sh`

**Goal:** Compile llama.cpp from source for a specific SM version, package it
as a versioned tarball, and optionally upload to GitHub Releases.

### Function signatures

```bash
# Print usage and exit 0
usage()

# Verify all required tools are present: git, cmake, ninja, jq, nvcc, curl.
# If --upload flag is set, also check for gh CLI.
# Args: $1 = upload_flag (bool: true/false)
# Exits 1 with list of missing tools if any are absent.
check_deps()

# Resolve "latest" to an actual llama.cpp release tag by querying GitHub API.
# Args: none
# Returns: tag string like "b4200"
# Exits 1 if the API call fails.
fetch_latest_version()

# Auto-detect SM version from the local GPU using detect.sh logic.
# Internally calls lookup_sm() from detect.sh (source it, don't duplicate).
# Args: $1 = path to gpu_map.json
# Returns: SM string like "89"
# Exits 1 if no GPU found or SM unknown.
detect_sm()

# Detect installed CUDA toolkit version from nvcc.
# Returns: version string like "12.4"
# Exits 1 if nvcc not found.
detect_cuda_version()

# Clone llama.cpp to a temp dir, or fetch + checkout if already cloned.
# Args: $1 = target_version (tag), $2 = src_dir (path)
# Returns: nothing (populates $2)
# Exits 1 on git failure.
prepare_source()

# Run cmake configure + build + install.
# Args: $1 = src_dir, $2 = sm_version, $3 = build_jobs, $4 = install_dir
# Returns: nothing
# Exits 1 on cmake or build failure.
# Must print progress updates (Configuring... / Compiling... / Installing...)
build()

# Package the install dir into a named tarball and generate SHA256.
# Args: $1 = install_dir, $2 = sm, $3 = llama_version, $4 = cuda_version, $5 = output_dir
# Returns: absolute path to the created .tar.gz file (echoed to stdout)
# Naming: llama-{version}-linux-cuda{cuda_ver}-sm{sm}-x64.tar.gz
package()

# Upload the tarball and its .sha256 to a GitHub Release.
# Creates the release if it does not exist.
# Args: $1 = archive_path, $2 = llama_version, $3 = github_repo
# Exits 1 if gh CLI not authenticated or upload fails.
upload_release()

# Main entrypoint. Orchestrates: check_deps → resolve version → detect SM →
# detect CUDA → prepare_source → build → package → [upload]
main()
```

### CLI interface

```
Usage: build.sh [OPTIONS]

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
```

### Edge cases to handle
- `--sm` not provided and no GPU detected → exit 1 with suggestion to use `--sm`
- `--version` tag does not exist on GitHub → exit 1 with clear message
- cmake configure fails → exit 1, print the cmake error output, suggest checking CUDA installation
- Binary already exists in output dir → skip build, print warning, continue to upload if `--upload`
- `--upload` with no `GITHUB_TOKEN` and no `gh` auth → exit 1 before building (fail fast)
- `--dry-run` → print every step that would happen, exit 0 without doing anything
- Build directory already exists from a previous failed build → clean it before rebuilding

### Acceptance criteria
- [ ] `./scripts/build.sh --help` exits 0
- [ ] `./scripts/build.sh --dry-run --sm 89 --version b4200` prints plan and exits 0
- [ ] `./scripts/build.sh --sm 89` produces a correctly named `.tar.gz` and `.sha256` in `./dist`
- [ ] The tarball contains runnable `llama-cli`, `llama-server`, `llama-bench` binaries
- [ ] `./scripts/build.sh --upload --sm 89` fails fast with clear error if `gh` not authenticated
- [ ] Running `build.sh` twice for the same version skips re-build (idempotent)

---

## TASK 4 — `scripts/pull.sh`

**Goal:** Detect the local GPU, find the matching pre-built binary on GitHub
Releases, download it, verify checksum, and install it.

### Function signatures

```bash
# Print usage and exit 0
usage()

# Check deps: curl, jq, tar. Exit 1 with list if missing.
check_deps()

# Fetch the release JSON from GitHub API for a given repo + version tag.
# Args: $1 = github_repo, $2 = version ("latest" is resolved here)
# Returns: full release JSON (echoed to stdout)
# Exits 1 on API failure or release not found.
fetch_release_json()

# Given release JSON and an SM version, find the matching asset URL and name.
# Matching rule: asset name must contain "sm{sm}" AND "linux" AND NOT ".sha256"
# Args: $1 = release_json, $2 = sm_version
# Returns: "<asset_name>|<asset_url>" pipe-delimited string, or empty if not found
find_asset()

# Download a URL to a destination path with a progress bar.
# Args: $1 = url, $2 = dest_path
# Exits 1 on curl failure.
download_file()

# Verify a file against its expected SHA256 hash fetched from a URL.
# Args: $1 = file_path, $2 = sha256_url
# Exits 1 if hash doesn't match. Print both expected and actual on failure.
verify_checksum()

# Extract the tarball and set up symlinks to main binaries.
# Symlink targets: llama-cli, llama-server, llama-bench (if they exist in archive)
# Args: $1 = archive_path, $2 = install_dir
# Returns: nothing
install_binary()

# Print all available binary assets for a given release (non-.sha256 files only).
# Args: $1 = release_json
list_available()

# Main entrypoint.
main()
```

### CLI interface

```
Usage: pull.sh [OPTIONS]

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
```

### Edge cases to handle
- No GPU and no `--sm` provided → exit 1 with message to use `--sm`
- Release not found on GitHub → exit 1, suggest `--list` to see available versions
- No binary found for the detected SM → exit 1, print all available SMs, suggest `build.sh`
- SHA256 mismatch → exit 1, delete the downloaded file, print both hashes
- Install dir not writable → exit 1 with clear permission error
- Binary already installed at same version → skip unless `--force`
- `--list` with no repo set → exit 1 before making any network calls
- Partial download (interrupted) → detect via incomplete file, re-download

### Acceptance criteria
- [ ] `./scripts/pull.sh --help` exits 0
- [ ] `./scripts/pull.sh --list --repo owner/repo` prints asset names and exits 0
- [ ] `./scripts/pull.sh --dry-run` prints what would happen and exits 0
- [ ] SHA256 mismatch causes exit 1 and deletes the bad file
- [ ] After successful pull, `~/.local/bin/llama/llama-cli --version` works
- [ ] Running pull twice at same version skips re-download (idempotent)
- [ ] `--force` re-downloads even if already installed

---

## TASK 5 — `scripts/verify.sh`

**Goal:** Standalone checksum verifier for a locally downloaded binary.
Simple, single-purpose, easy to audit.

### Function signatures

```bash
usage()

# Verify a local file against a SHA256 hash.
# The hash can come from: a local .sha256 file, a URL, or a raw hash string.
# Args: $1 = file_path, $2 = hash_source (path, URL, or 64-char hex string)
# Returns: 0 on match, 1 on mismatch
# Always prints both expected and actual hash.
verify()

main()
```

### CLI interface

```
Usage: verify.sh <file> [<sha256-source>]

Arguments:
  file              Path to the file to verify.
  sha256-source     One of:
                      - Path to a .sha256 file
                      - A URL pointing to a .sha256 file
                      - A raw 64-character SHA256 hex string
                    If omitted, looks for <file>.sha256 in same directory.

Options:
  -h, --help        Show this help.
```

### Acceptance criteria
- [ ] `./scripts/verify.sh file.tar.gz file.tar.gz.sha256` exits 0 on match
- [ ] Exits 1 on mismatch and prints both hashes
- [ ] Accepts a URL as the sha256 source (fetches with curl)
- [ ] Accepts a raw hash string as the sha256 source
- [ ] If no sha256 source given, auto-discovers `<file>.sha256` in same dir
- [ ] Missing source file → exit 1 with clear error

---

## TASK 6 — `scripts/list.sh`

**Goal:** Query GitHub Releases and display available binaries in a clean,
filterable table. Helps users discover what's available before pulling.

### Function signatures

```bash
usage()

# Fetch all releases (paginated) or a single release for a given version.
# Args: $1 = github_repo, $2 = version ("all" fetches last 10 releases)
# Returns: JSON array of release objects
fetch_releases()

# Format and print a release's assets as a table.
# Args: $1 = release_json
# Columns: Version | SM | Architecture | CUDA | Size | Published
print_release_table()

main()
```

### CLI interface

```
Usage: list.sh [OPTIONS]

Options:
  --repo <owner/repo>   GitHub repo to query. Overrides LLAMA_DEPLOY_REPO.
  --version <tag>       Show only this version. Default: latest.
  --all                 Show all available releases (last 10).
  --sm <version>        Filter by SM version.
  --json                Output as JSON.
  -h, --help            Show this help.
```

### Expected table output (example)

```
Available binaries — llamaup / b4200

  Version   SM    Architecture              CUDA    Size     Published
  -------   ----  ------------------------  ------  -------  -------------------
  b4200     75    Turing                    12.4    48 MB    2025-03-01 14:22 UTC
  b4200     80    Ampere HPC                12.4    51 MB    2025-03-01 14:22 UTC
  b4200     86    Ampere Consumer           12.4    51 MB    2025-03-01 14:22 UTC
  b4200     89    Ada Lovelace              12.4    52 MB    2025-03-01 14:22 UTC
  b4200     90    Hopper                    12.4    53 MB    2025-03-01 14:22 UTC
  b4200     100   Blackwell Datacenter      12.8    55 MB    2025-03-01 14:22 UTC
  b4200     101   Blackwell Consumer        12.8    55 MB    2025-03-01 14:22 UTC
  b4200     120   Blackwell Workstation     12.8    55 MB    2025-03-01 14:22 UTC

  Download: ./scripts/pull.sh --version b4200 [--sm <sm>]
```

### Acceptance criteria
- [ ] `./scripts/list.sh --help` exits 0
- [ ] `./scripts/list.sh --repo owner/repo` prints a formatted table
- [ ] `./scripts/list.sh --all` shows multiple releases
- [ ] `./scripts/list.sh --sm 89` filters to only SM 89 rows
- [ ] `./scripts/list.sh --json` outputs valid JSON
- [ ] No repo set → exit 1 before making any network call

---

## TASK 7 — `.github/workflows/build.yml`

**Goal:** CI pipeline that builds all SM versions in a matrix, runs a smoke
test, and publishes a GitHub Release with all binaries attached.

### Pipeline structure

```
Job 1: resolve-version
  - Resolve "latest" or use workflow_dispatch input
  - Check if release already exists in this repo (skip if so)
  - Output: version string, already_built bool

Job 2: build (matrix)
  - Depends on: resolve-version (already_built == false)
  - Matrix: sm × cuda_image (see table below)
  - Container: nvidia/cuda:{cuda_version}-devel-ubuntu22.04
  - Steps:
      1. Checkout this repo
      2. Install deps (cmake, ninja, git, jq, curl)
      3. Cache llama.cpp source by version tag
      4. Clone/checkout llama.cpp at resolved version
      5. cmake configure with -DCMAKE_CUDA_ARCHITECTURES={sm}
      6. cmake build -j $(nproc)
      7. cmake install
      8. Package → llama-{version}-linux-cuda{cuda}-sm{sm}-x64.tar.gz
      9. sha256sum → paired .sha256 file
      10. Upload as GitHub Actions artifact

Job 3: smoke-test (matrix, same SM matrix)
  - Depends on: build
  - Container: nvidia/cuda:{cuda_version}-runtime-ubuntu22.04
  - Downloads the artifact from Job 2
  - Extracts and runs: ./llama-cli --version
  - Exits 1 if the binary fails to run or version string is empty

Job 4: release
  - Depends on: smoke-test (all matrix jobs passed)
  - Downloads all artifacts
  - Creates GitHub Release with tag = resolved version
  - Uploads all .tar.gz and .sha256 files
  - Release body includes GPU table and quick install command
```

### Build matrix

| SM  | CUDA Container Version | Min CUDA |
|-----|------------------------|----------|
| 75  | 12.4.0                 | 11.0     |
| 80  | 12.4.0                 | 11.0     |
| 86  | 12.4.0                 | 11.1     |
| 89  | 12.4.0                 | 11.8     |
| 90  | 12.4.0                 | 11.8     |
| 100 | 12.8.0                 | 12.8     |
| 101 | 12.8.0                 | 12.8     |
| 120 | 12.8.0                 | 12.8     |

### Trigger conditions

```yaml
on:
  schedule:
    - cron: '0 4 * * *'         # daily at 04:00 UTC
  workflow_dispatch:
    inputs:
      llama_version:            # specific tag or "latest"
      sm_versions:              # comma-separated override, e.g. "89,90"
      force_rebuild:            # bool: rebuild even if release exists
  repository_dispatch:
    types: [new-llama-release]  # external webhook trigger
```

### Acceptance criteria
- [ ] Workflow file is valid YAML (`yamllint .github/workflows/build.yml`)
- [ ] Matrix covers all 8 SM versions
- [ ] `resolve-version` job correctly skips if release already exists
- [ ] `smoke-test` job fails the whole pipeline if any binary doesn't run
- [ ] `release` job only runs if ALL smoke tests pass
- [ ] `force_rebuild` input bypasses the already-built check
- [ ] Manual `sm_versions` input correctly limits the matrix to specified SMs

---

## TASK 8 — `CONTRIBUTING.md`

**Goal:** Clear guide for community contributors. Three main audiences:
users who found a wrong GPU mapping, users who want to add a new GPU,
and developers who want to contribute code.

### Required sections

1. **How to add or fix a GPU mapping**
   - Where `gpu_map.json` lives
   - How to find the correct SM version (link to NVIDIA's official CUDA GPU page)
   - How to verify: run `detect.sh` before and after
   - PR checklist

2. **How to contribute a binary for a new SM version**
   - Prerequisites (CUDA toolkit, cmake, ninja)
   - Steps: clone → `build.sh --sm X --upload`
   - How to verify the upload worked: `list.sh`

3. **How to report a bad or missing binary**
   - Link to issue templates
   - What info to include (`detect.sh --json` output)

4. **Code contribution guidelines**
   - All scripts must pass `shellcheck`
   - Test on at least one real GPU before submitting
   - Keep scripts dependency-minimal (no Python, no Node)

### Acceptance criteria
- [ ] File exists and is readable
- [ ] All 4 sections present
- [ ] Links to NVIDIA CUDA GPU compute capability page
- [ ] Mentions `shellcheck` as a required linting step

---

## TASK 9 — GitHub Issue Templates

### `.github/ISSUE_TEMPLATE/wrong_sm.md`

```markdown
---
name: Wrong GPU/SM mapping
about: The detected SM version for my GPU is incorrect
labels: gpu-map
---

**GPU model (from nvidia-smi or detect.sh):**

**SM version detected:**

**Correct SM version (with source):**

**Output of `detect.sh --json`:**
```json
paste here
```
```

### `.github/ISSUE_TEMPLATE/bad_binary.md`

```markdown
---
name: Binary doesn't work
about: The downloaded binary crashes or fails to run
labels: binary
---

**llama.cpp version:**
**SM version:**
**CUDA version:**
**OS + kernel:**

**Output of `detect.sh --json`:**
```json
paste here
```

**Error output:**
```
paste here
```
```

### Acceptance criteria
- [ ] Both files exist under `.github/ISSUE_TEMPLATE/`
- [ ] Both have correct YAML frontmatter with `name`, `about`, `labels`

---

## TASK 10 — End-to-end validation

**Goal:** Verify the full pipeline works together before the project is
considered complete.

### Steps

1. Run `detect.sh` on a machine with a known GPU — confirm output matches expected SM
2. Run `build.sh --dry-run --sm 89 --version b4200` — confirm dry-run output is correct
3. Run a real `build.sh --sm 89` — confirm tarball is created with correct naming
4. Run `verify.sh` on the tarball — confirm SHA256 passes
5. Upload to GitHub Releases manually using `build.sh --upload`
6. Run `list.sh` — confirm the binary appears in the table
7. Run `pull.sh` on a different machine — confirm it detects GPU, downloads, verifies, installs
8. Run `llama-cli --version` — confirm the installed binary works

### Acceptance criteria
- [ ] All 8 steps complete without errors
- [ ] Binary installed by `pull.sh` actually runs
- [ ] `shellcheck scripts/*.sh` returns 0 warnings

---

## Global constraints (apply to every task)

- Every script: `set -euo pipefail` at the top
- Every script: `--help` flag supported, exits 0
- Every script: resolves its own path with `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` so it works from any CWD
- Every script: sources `detect.sh` functions rather than duplicating GPU detection logic
- Colour output constants defined once per script: `RED GREEN YELLOW CYAN BOLD RESET`
- No script should silently succeed when something goes wrong — prefer loud failures
- All user-facing error messages must suggest a corrective action
- `shellcheck` must pass on all scripts with zero warnings