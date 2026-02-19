# CLAUDE.md — Project Context for Claude Code

## What this project is

`llamaup` is an open source command-line toolchain that solves a real gap:
**llama.cpp ships no pre-built Linux CUDA binaries.** This project builds them,
stores them on GitHub Releases, and lets any user pull the right one for their
GPU in seconds — without compiling.

The core insight: you don't need one binary per GPU model. You need one per
**SM (Streaming Multiprocessor) version**. Many GPUs share the same SM, so the
binary matrix is small.

---

## Repository structure

```bash
llamaup/
├── scripts/
│   ├── build.sh          # compile llama.cpp for a given SM, package, upload
│   ├── pull.sh           # detect GPU, download right binary, install
│   ├── detect.sh         # report local GPU / SM / CUDA info (diagnostic)
│   ├── verify.sh         # verify SHA256 of a local binary
│   └── list.sh           # list all available binaries in the release store
├── configs/
│   └── gpu_map.json      # GPU model name substrings → SM version
├── .github/
│   ├── workflows/
│   │   └── build.yml     # CI matrix: builds all SM versions, creates GH Release
│   └── ISSUE_TEMPLATE/
│       ├── wrong_sm.md
│       └── bad_binary.md
├── CLAUDE.md             # this file
├── AGENTS.md             # full implementation spec
├── CONTRIBUTING.md
├── README.md
└── LICENSE
```

---

## GPU → SM version map (critical knowledge)

| SM     | Architecture          | Key GPUs                                              |
|--------|-----------------------|-------------------------------------------------------|
| sm_75  | Turing                | T4, RTX 2060/2070/2080, Quadro RTX series             |
| sm_80  | Ampere HPC            | A100, A30                                             |
| sm_86  | Ampere Consumer       | RTX 3060–3090, A10, A40, RTX A2000–A6000             |
| sm_89  | Ada Lovelace          | RTX 4060–4090, L4, L40, L40S, RTX 6000 Ada           |
| sm_90  | Hopper                | H100, H200, GH200                                     |
| sm_100 | Blackwell Datacenter  | B100, B200, GB200                                     |
| sm_101 | Blackwell Consumer    | RTX 5060–5090                                         |
| sm_120 | Blackwell Workstation | RTX PRO 6000/5000/4500/4000/2000 Blackwell            |

**Important Blackwell nuance:** Blackwell has 3 distinct SM variants (sm_100,
sm_101, sm_120). sm_101 is consumer RTX 50-series. sm_120 is workstation RTX PRO.
They are NOT the same and cannot share binaries. Requires CUDA 12.8+.

---

## Binary naming convention

```bash
llama-{version}-linux-cuda{cuda_major.minor}-sm{sm}-x64.tar.gz
llama-{version}-linux-cuda{cuda_major.minor}-sm{sm}-x64.tar.gz.sha256

Example:
  llama-b4200-linux-cuda12.4-sm89-x64.tar.gz
  llama-b4200-linux-cuda12.4-sm89-x64.tar.gz.sha256
```

---

## Key design decisions

- **All scripts are pure bash** — no Python, no Node. Target: any Linux machine
  with standard coreutils. Only external tools needed are `curl`, `jq`, `cmake`,
  `ninja`, `nvidia-smi`, `nvcc` (where relevant).
- **GitHub Releases as the binary store** — free, versioned, content-addressed
  via SHA256, accessible via the `gh` CLI and raw `curl`.
- **SM auto-detection** — scripts detect the local GPU via `nvidia-smi` and look
  up its SM in `gpu_map.json` using `jq`. Never hardcode SM in runtime paths.
- **SHA256 always** — every binary upload must have a paired `.sha256` file.
  Verification is on by default in `pull.sh`.
- **CI uses nvidia/cuda Docker containers** — no GPU hardware needed on GitHub
  Actions runners. Compilation happens inside the container.
- **Idempotent** — running `build.sh` or `pull.sh` twice should be safe. Check
  before overwriting.

---

## Environment variables used across scripts

| Variable             | Used in         | Purpose                                      |
|----------------------|-----------------|----------------------------------------------|
| `LLAMA_DEPLOY_REPO`  | all scripts     | GitHub repo (owner/repo) for releases        |
| `GITHUB_TOKEN`       | build.sh        | Auth for `gh release upload`                 |
| `LLAMA_DEPLOY_DEBUG` | all scripts     | If set to `1`, enable verbose/debug output   |

---

## Coding standards for this project

- Every script starts with `set -euo pipefail`
- All functions have a comment block describing purpose, args, and return value
- Use named local variables — no positional `$1` without immediately assigning
- Colour output: CYAN for info, GREEN for success, YELLOW for warnings, RED for errors
- Every `error()` call must exit with code 1
- `--dry-run` flag must be supported in build.sh and pull.sh
- `--help` flag must print usage and exit 0 in every script
- No hardcoded paths — use variables and defaults that can be overridden