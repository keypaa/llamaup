# llamaup

**Pre-built Linux CUDA binaries for [llama.cpp](https://github.com/ggerganov/llama.cpp), organized by GPU architecture.**

No more compiling on every machine. Build once per SM version, store the binary, pull it anywhere in seconds.


[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/keypaa/llamaup)

---

## The problem

The official llama.cpp releases ship pre-built Windows CUDA binaries but **nothing for Linux CUDA**. If you're running llama.cpp on Linux across multiple GPU types (T4, A100, L40S, RTX 4090, H100...) you have to compile from source every time — on every machine, for every new release.

## The solution

This repo gives you:

- **`scripts/pull.sh`** — detects your GPU, downloads the right pre-built binary, and installs it
- **`scripts/build.sh`** — builds llama.cpp for a specific GPU SM version and uploads to GitHub Releases
- **`scripts/detect.sh`** — diagnostic tool to check your GPU, SM version, CUDA, and driver info
- **`scripts/list.sh`** — lists all available pre-built binaries in the release store
- **`scripts/verify.sh`** — verify SHA256 checksums of downloaded binaries
- **`scripts/cleanup.sh`** — manage and remove old installed llama.cpp versions
- **`configs/gpu_map.json`** — maps GPU model names → SM versions
- **`.github/workflows/build.yml`** — CI pipeline that auto-builds all SM versions on new llama.cpp releases

---

## Quick start

### On a machine where you want to run llama.cpp

```bash
# Install required tools (if not already installed)
# Ubuntu/Debian: sudo apt install -y curl jq tar
# RHEL/CentOS: sudo yum install -y curl jq tar

git clone https://github.com/keypaa/llamaup
cd llamaup

# If scripts aren't executable (e.g., downloaded as ZIP):
chmod +x scripts/*.sh

# Set the repo that hosts your pre-built binaries
export LLAMA_DEPLOY_REPO=keypaa/llamaup

# Pull the right binary for your GPU (auto-detected)
./scripts/pull.sh

# Or pull a specific version
./scripts/pull.sh --version b4102
```

That's it. The script detects your GPU, finds the matching binary, verifies the checksum, and installs it to `~/.local/bin/llama`.

**Add to your PATH:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Using llama.cpp (Quick Reference)

After installation, you have three main binaries available:

### 1. **llama-cli** — Command-line inference

> **💡 Tip:** Modern llama.cpp versions (8000+) can download models automatically! Use `-hf user/repo:quant` to download from Hugging Face without manual steps.

```bash
# Automatic download + run (recommended for newer versions)
llama-cli -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M \
  -cnv \
  -t 8 \
  -c 8192 \
  --temp 0.7

# Or download manually first (if you prefer)
huggingface-cli download bartowski/Qwen2.5-7B-Instruct-GGUF Qwen2.5-7B-Instruct-Q4_K_M.gguf --local-dir ./models

# Then run with local file
llama-cli -m ./models/Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  -cnv \
  -n 512 \
  --temp 0.7 \
  -t 8 \
  -c 8192
```

**Model download options (built-in):**
- `-hf <user>/<repo>[:quant]` — Download from Hugging Face (e.g., `bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M`)
- `-mu <url>` — Download from direct URL
- `--hf-token` — Use HuggingFace token for private/gated models

**Common flags:**
- `-m` — path to your `.gguf` model file
- `-p` — prompt text
- `-n` — max tokens to generate (default: -1 = unlimited)
- `-t` — number of threads (use your CPU core count)
- `-c` — context size (default: loaded from model)
- `--temp` — temperature (0.0 = deterministic, 1.0 = creative)
- `-cnv` / `--conversation` — conversation mode (interactive, hides special tokens)
- `-st` / `--single-turn` — run conversation for a single turn, then exit
- `-sys` / `--system-prompt` — system prompt to use with chat models
- `--color` — colorize output (`on`, `off`, or `auto`)

> **Note:** Run `llama-cli --help` to see all available options for your version.

### 2. **llama-server** — HTTP API server (recommended for chat)

```bash
# Start the server
llama-server -m ./models/Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  -c 8192 \
  --port 8080 \
  --host 0.0.0.0

# Access the web UI at http://localhost:8080
# Or use the API:
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "temperature": 0.7,
    "max_tokens": 512
  }'
```

The server provides an OpenAI-compatible API — great for integrations with tools like Open WebUI, LobeChat, or your own apps.

### 3. **llama-bench** — Performance benchmarking

```bash
# Benchmark prompt processing and generation speed
llama-bench -m ./models/Qwen2.5-7B-Instruct-Q4_K_M.gguf
```

### Getting models

**Option 1: Built-in download (easiest, requires llama.cpp 8000+)**
```bash
# llama.cpp downloads the model automatically
llama-cli -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M -cnv -t 8
llama-server -hf bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M -c 8192
```

**Option 2: Manual download**
- [Hugging Face](https://huggingface.co/models?search=gguf) — search for "gguf"
- Popular quantizers: [bartowski](https://huggingface.co/bartowski), [mradermacher](https://huggingface.co/mradermacher), [TheBloke](https://huggingface.co/TheBloke)

```bash
# Using huggingface-cli
huggingface-cli download bartowski/Qwen2.5-7B-Instruct-GGUF Qwen2.5-7B-Instruct-Q4_K_M.gguf --local-dir ./models
```

**Quantization guide:**
- `Q4_K_M` — best quality/size tradeoff (recommended)
- `Q5_K_M` — higher quality, larger size
- `Q8_0` — near-original quality, large
- `Q3_K_M` — smaller, lower quality

### Full help

```bash
llama-cli --help
llama-server --help
llama-bench --help
```

### What's included in each binary

Each pre-built archive contains the following binaries:

**Core tools (always included):**
- `llama-cli` — Command-line inference and chat
- `llama-server` — HTTP API server with web UI
- `llama-bench` — Performance benchmarking

**Additional utilities (version-dependent):**
- `llama-quantize` — Convert and quantize models to GGUF format
- `llama-embedding` — Generate embeddings for input text
- `llama-export-lora` — Export LoRA adapters
- `llama-perplexity` — Calculate perplexity on test data
- `llama-tokenize` — Tokenize text with a model's tokenizer
- `llama-gritlm` — GRITLM-specific inference
- `llama-lookahead` — Experimental lookahead decoding
- `llama-parallel` — Multi-request parallel inference
- `llama-simple` — Minimal example binary
- `llama-speculative` — Speculative decoding
- `llama-batched-bench` — Batched inference benchmark
- `llama-retrieval` — RAG/retrieval example
- `llama-cvector-generator` — Control vector generation
- `llama-imatrix` — Importance matrix generation for better quantization

The exact set of binaries varies by llama.cpp version. The three core tools (`llama-cli`, `llama-server`, `llama-bench`) are guaranteed to be present and are the primary focus of smoke tests in CI.

---

## 🔍 Browsing GGUF Models — `llama-models`

**Optional TUI tool for discovering and downloading GGUF models from HuggingFace.**

`llama-models` is an interactive browser that helps you search, select, and download GGUF models without leaving the terminal. It supports two modes:

- **Premium mode** (recommended): Beautiful TUI with [gum](https://github.com/charmbracelet/gum) + fast downloads with `aria2c`
- **Minimal mode** (fallback): Bash-native menus with `curl` — zero extra dependencies

### Quick Start

```bash
# Make the script executable first (only needed once)
chmod +x scripts/llama-models

# Search for models (auto-detects best available mode)
./scripts/llama-models search qwen2.5-7b-instruct

# Install premium dependencies for better experience (optional)
./scripts/llama-models --install-deps

# List popular models
./scripts/llama-models list

# Force minimal mode (no TUI dependencies)
./scripts/llama-models --mode=minimal search llama-3.2

# Force premium mode (requires gum + aria2c)
./scripts/llama-models --mode=premium search mixtral
```

### Features

✅ **Smart search**: Query HuggingFace's GGUF model collection  
✅ **Interactive selection**: Choose models and quantizations with arrow keys  
✅ **Multi-select** (premium mode): Download multiple models at once  
✅ **Fast downloads**: `aria2c` multi-connection downloads (premium mode) — typically 3–8x faster than llama.cpp's built-in `-hf` flag, which uses a single TCP connection  
✅ **Fallback mode**: Works everywhere with just `curl` and `jq`  
✅ **Smart storage**: Models saved to `~/.local/share/llama-models/`  

### Installation

**Base requirements** (always needed):
```bash
# Ubuntu/Debian
sudo apt install -y curl jq

# RHEL/Fedora
sudo yum install -y curl jq

# Arch
sudo pacman -S curl jq

# macOS
brew install curl jq
```

**Premium mode dependencies** (optional but recommended):

```bash
# Let the script install them for you (easiest)
./scripts/llama-models --install-deps

# Or install manually:
# Ubuntu/Debian
sudo apt install -y aria2
# gum: download from https://github.com/charmbracelet/gum/releases

# macOS
brew install gum aria2
```

The `--install-deps` command will:
- Install `aria2c` via your system package manager (may prompt for sudo)
- Download and install `gum` binary to `~/.local/bin/`
- Add `~/.local/bin` to your PATH if needed

### Usage

#### Search for models

```bash
# Interactive search
./scripts/llama-models search qwen2.5-7b-instruct

# Search with different query
./scripts/llama-models search "mixtral 8x7b"

# Search and list more results
./scripts/llama-models search llama-3 --limit 20
```

**Workflow:**
1. Script queries HuggingFace API
2. Displays matching models sorted by downloads
3. You select one or more models (arrow keys + Space in premium mode)
4. Script lists available quantizations (Q4_K_M, Q5_K_M, etc.)
5. You select quantization(s)
6. Downloads begin automatically

#### List popular models

```bash
# Show top 10 most downloaded GGUF models
./scripts/llama-models list

# See more results
./scripts/llama-models list --limit 20
```

#### Mode selection

```bash
# Auto-detect (default — uses premium if gum + aria2c available)
./scripts/llama-models search qwen

# Force minimal mode
./scripts/llama-models --mode=minimal search qwen

# Force premium mode (fails if deps missing)
./scripts/llama-models --mode=premium search qwen
```

### Modes Compared

| Feature | Minimal Mode | Premium Mode |
|---------|-------------|-------------|
| **Dependencies** | `curl`, `jq` only | + `gum`, `aria2c` |
| **UI** | Bash `select` menu | Charm `gum` TUI |
| **Download** | Single-connection `curl` | Multi-connection `aria2c` |
| **Multi-select** | No (one at a time) | Yes (Space to toggle) |
| **Speed** | Standard | 3-8x faster downloads |
| **Portability** | Works everywhere | Requires modern Linux/macOS |

### Examples

**Find and download a specific model:**
```bash
./scripts/llama-models search "qwen2.5-7b-instruct"
# → Select model from list
# → Select Q4_K_M quantization
# → Downloads to ~/.local/share/llama-models/
```

**Download multiple quantizations** (premium mode):
```bash
./scripts/llama-models --mode=premium search "llama-3.2-3b"
# → Press Space to select multiple models
# → Press Space to select multiple quantizations (Q4_K_M, Q5_K_M, Q8_0)
# → Downloads all selected files in parallel
```

**Browse popular models:**
```bash
./scripts/llama-models list
# → Shows top 10 GGUF models by download count
```

### Where are models stored?

Default: `~/.local/share/llama-models/`

Override with environment variable:
```bash
export LLAMA_MODELS_DIR=/mnt/storage/models
./scripts/llama-models search qwen
```

Models are saved as: `{model-id}__{filename}.gguf`

Example: `bartowski__Qwen2.5-7B-Instruct-Q4_K_M.gguf`

### Using downloaded models

After downloading, use them with llama.cpp:

```bash
# Find your model
ls -lh ~/.local/share/llama-models/

# Run with llama-cli
llama-cli -m ~/.local/share/llama-models/bartowski__Qwen2.5-7B-Instruct-Q4_K_M.gguf -cnv

# Start llama-server
llama-server -m ~/.local/share/llama-models/bartowski__Qwen2.5-7B-Instruct-Q4_K_M.gguf -c 8192
```

### Performance Comparison

**Download time for a 4.5 GB model** (Qwen2.5-7B Q4_K_M):

| Mode | Tool | Time | Speed |
|------|------|------|-------|
| Minimal | `curl` | ~8 min | 1x (baseline) |
| Premium | `aria2c` 8 connections | ~2 min | **4x faster** |

> Actual speedup depends on your network bandwidth and HuggingFace CDN performance.

### Options

```bash
llama-models [OPTIONS] <command>

Commands:
  search <query>      Search for GGUF models on HuggingFace
  list                List popular GGUF models (sorted by downloads)

Options:
  --mode=<mode>       Force mode: 'minimal' or 'premium'
  --install-deps      Install premium dependencies (gum + aria2c)
  --limit=<n>         Number of results to show (default: 10)
  --version           Show version
  --help              Show help
```

### Troubleshooting

**"gum: command not found" when using premium mode**

Premium mode requires `gum`. Install it:
```bash
./scripts/llama-models --install-deps
# or manually from: https://github.com/charmbracelet/gum/releases
```

Or use minimal mode:
```bash
./scripts/llama-models --mode=minimal search qwen
```

**"aria2c: command not found" in premium mode**

Install via package manager:
```bash
# Ubuntu/Debian
sudo apt install aria2

# macOS
brew install aria2
```

**No models found for search query**

Try:
- Broader search terms (e.g., "llama" instead of "llama-3.2-3b-instruct-q4")
- Check HuggingFace directly: https://huggingface.co/models?search=your+query&filter=gguf
- Use `./scripts/llama-models list` to browse popular models

**Download fails or is very slow**

- Check your internet connection
- Try switching to minimal mode: `--mode=minimal`
- HuggingFace CDN may be slow from your location — this is normal

**Model not compatible with llama.cpp**

Make sure you're downloading GGUF models (not safetensors or PyTorch). All models found by `llama-models` are pre-filtered to GGUF format.

---

## Scripts Reference

### `scripts/pull.sh` — Download and install pre-built binaries

The main install tool. Detects your GPU, downloads the matching binary, verifies checksum, and installs.

```bash
# Basic usage (auto-detects GPU)
./scripts/pull.sh

# List available binaries for a version
./scripts/pull.sh --list --version b4102

# Pull specific version and SM
./scripts/pull.sh --version b4102 --sm 89

# Custom install directory
./scripts/pull.sh --install-dir /opt/llama

# Dry run (see what would happen)
./scripts/pull.sh --dry-run
```

**Options:**
- `--version <tag>` — llama.cpp release tag (default: latest)
- `--repo <owner/repo>` — GitHub repo to pull from
- `--sm <version>` — Override SM auto-detection
- `--install-dir <dir>` — Installation directory (default: `~/.local/bin/llama`)
- `--no-verify` — Skip SHA256 verification (not recommended)
- `--dry-run` — Show what would be downloaded without doing it
- `--list` — List all available binaries for this version
- `--force` — Re-download even if already installed

### `scripts/build.sh` — Build and package binaries

Compile llama.cpp from source for a specific SM version and optionally upload to GitHub Releases.

```bash
# Build for current GPU (auto-detected)
./scripts/build.sh

# Build for specific SM without uploading
./scripts/build.sh --sm 89 --version b4102

# Build and upload to releases
export GITHUB_TOKEN=your_token
./scripts/build.sh --sm 89 --upload --repo keypaa/llamaup

# Dry run
./scripts/build.sh --dry-run --sm 89
```

**Options:**
- `--sm <version>` — SM version to build for (auto-detected if omitted)
- `--version <tag>` — llama.cpp release tag (default: latest)
- `--cuda <version>` — CUDA version string for binary name (auto-detected)
- `--output <dir>` — Output directory for tarball (default: `./dist`)
- `--upload` — Upload to GitHub Releases after building
- `--repo <owner/repo>` — GitHub repo for upload
- `--jobs <n>` — Parallel build jobs (default: `nproc`)
- `--src-dir <dir>` — Where to clone llama.cpp (default: `/tmp/llamaup-src`)
- `--dry-run` — Print plan without executing

### `scripts/detect.sh` — Diagnostic and GPU detection

Reports detailed information about your GPU, SM version, CUDA toolkit, and driver. Used by other scripts for auto-detection and helpful for debugging.

```bash
# Human-readable report
./scripts/detect.sh

# JSON output (for scripts)
./scripts/detect.sh --json

# Validate GPU map for overlapping patterns
LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh
```

**Output includes:**
- All detected GPUs with their SM versions
- GPU architecture name
- Minimum CUDA version required
- Installed CUDA toolkit version
- NVIDIA driver version

**Options:**
- `--json` — Output as JSON instead of human-readable text
- `--gpu-map <path>` — Path to gpu_map.json (default: auto-detected)

### `scripts/list.sh` — List available binaries

Query GitHub Releases and display available pre-built binaries in a table format.

```bash
# List latest release binaries
./scripts/list.sh --repo keypaa/llamaup

# List specific version
./scripts/list.sh --version b4102

# Show all releases
./scripts/list.sh --all

# Filter by SM version
./scripts/list.sh --sm 89

# JSON output
./scripts/list.sh --json
```

**Options:**
- `--repo <owner/repo>` — GitHub repo to query
- `--version <tag>` — Show only this version (default: latest)
- `--all` — Show all available releases (last 10)
- `--sm <version>` — Filter by SM version
- `--json` — Output as JSON

### `scripts/verify.sh` — Verify file checksums

Standalone SHA256 checksum verifier for downloaded binaries.

```bash
# Verify with auto-discovered .sha256 file
./scripts/verify.sh file.tar.gz

# Verify with explicit .sha256 file
./scripts/verify.sh file.tar.gz file.tar.gz.sha256

# Verify with SHA256 from URL
./scripts/verify.sh file.tar.gz https://example.com/file.tar.gz.sha256

# Verify with raw hash string
./scripts/verify.sh file.tar.gz 1234567890abcdef...
```

**Arguments:**
- `<file>` — Path to file to verify
- `[sha256-source]` — .sha256 file path, URL, or raw hash (auto-discovered if omitted)

### `scripts/cleanup.sh` — Manage installed versions

List and remove old installed llama.cpp versions to save disk space.

```bash
# Interactive mode (prompts for each version)
./scripts/cleanup.sh

# Keep 2 most recent versions, remove rest
./scripts/cleanup.sh --keep 2

# Remove all versions (with confirmation)
./scripts/cleanup.sh --all

# Dry run (see what would be removed)
./scripts/cleanup.sh --dry-run --keep 1
```

**Options:**
- `--install-dir <dir>` — Installation root (default: `~/.local/bin/llama`)
- `--keep <n>` — Keep N most recent versions, remove rest
- `--all` — Remove all installed versions (prompts for confirmation)
- `--dry-run` — Show what would be removed without removing

---

## GPU → SM version map

Many GPUs share the same SM (Streaming Multiprocessor) architecture, so you don't need one binary per GPU model — just one per SM version.

| SM | Architecture | GPU Examples |
|---|---|---|
| `sm_75` | Turing | T4, RTX 2060/2070/2080, Quadro RTX |
| `sm_80` | Ampere (HPC) | A100, A30 |
| `sm_86` | Ampere (Consumer) | RTX 3060/3070/3080/3090, A10, A40, RTX A4000/A5000/A6000 |
| `sm_89` | Ada Lovelace | RTX 4060/4070/4080/4090, L4, L40, **L40S**, RTX 6000 Ada |
| `sm_90` | Hopper | H100, H200, GH200 |
| `sm_100` | Blackwell Datacenter | B100, B200, GB200 |
| `sm_101` | Blackwell Consumer | **RTX 5090**, RTX 5080, 5070 Ti, 5070, 5060 Ti, 5060 |
| `sm_120` | Blackwell Workstation | **RTX PRO 6000**, RTX PRO 5000/4500/4000/2000 |

> **Note:** The 4090 and L40S are both SM 89, so they share the same binary. Same idea for RTX PRO 6000 and RTX 5090 (both SM 100).

---

## Building binaries

### Build for your current machine's GPU (and upload)

```bash
export LLAMA_DEPLOY_REPO=keypaa/llamaup
export GITHUB_TOKEN=your_token

./scripts/build.sh --upload
```

### Build for a specific SM version

```bash
# Build for SM 89 (4090, L40S) without uploading
./scripts/build.sh --sm 89 --version b4102 --output ./dist

# Build for SM 80 (A100) and upload
./scripts/build.sh --sm 80 --upload
```

### Build options

```
--sm <version>      SM architecture version (e.g. 89). Auto-detected if omitted.
--version <tag>     llama.cpp release tag (e.g. b4102). Default: latest.
--cuda <version>    CUDA toolkit version. Default: auto-detected from nvcc.
--output <dir>      Where to store the built binary. Default: ./dist
--upload            Upload to GitHub Releases after building.
--repo <owner/repo> GitHub repo for upload.
--jobs <n>          Parallel build jobs. Default: nproc.
--dry-run           Print what would happen without doing it.
```

---

## Automatic builds via CI

Fork this repo, enable GitHub Actions, and every day the workflow checks for a new llama.cpp release and builds binaries for all SM versions automatically.

The workflow runs inside official `nvidia/cuda` Docker containers — no GPU hardware required for the CI runners.

**Supported SM versions built in CI:**

| SM | Architecture | CUDA Container |
|---|---|---|
| 75 | Turing | cuda:12.4-devel-ubuntu22.04 |
| 80 | Ampere HPC | cuda:12.4-devel-ubuntu22.04 |
| 86 | Ampere Consumer | cuda:12.4-devel-ubuntu22.04 |
| 89 | Ada Lovelace | cuda:12.4-devel-ubuntu22.04 |
| 90 | Hopper | cuda:12.4-devel-ubuntu22.04 |
| 100 | Blackwell | cuda:12.6-devel-ubuntu22.04 |

You can also trigger a build manually from the Actions tab with a specific version or a custom set of SM targets.

---

## Pull options

```
--version <tag>       llama.cpp release tag. Default: latest.
--repo <owner/repo>   GitHub repo to pull from.
--sm <version>        Override SM version (skip auto-detection).
--install-dir <dir>   Where to install. Default: ~/.local/bin/llama
--no-verify           Skip SHA256 verification.
--dry-run             Show what would be downloaded without doing it.
--list                List all available binaries for this version.
```

### Examples

```bash
# See what's available
./scripts/pull.sh --list

# Pull latest for current GPU
./scripts/pull.sh

# Pull specific version, custom install dir
./scripts/pull.sh --version b4102 --install-dir /opt/llama

# Pull for a specific SM without nvidia-smi (e.g. inside Docker)
./scripts/pull.sh --sm 89

# Dry run — see what would happen
./scripts/pull.sh --dry-run
```

---

## Binary naming convention

```
llama-{version}-linux-cuda{cuda_ver}-sm{sm}-x64.tar.gz

Examples:
  llama-b4102-linux-cuda12.8-sm89-x64.tar.gz   ← for 4090, L40S
  llama-b4102-linux-cuda12.4-sm80-x64.tar.gz   ← for A100
  llama-b4102-linux-cuda12.6-sm100-x64.tar.gz  ← for H100, RTX PRO 6000
```

Each archive contains the full llama.cpp install tree (binaries, libraries). A corresponding `.sha256` file is always uploaded alongside it.

---

## Setup: forking this repo

1. Fork this repo to your GitHub account or org
2. Set `LLAMA_DEPLOY_REPO=keypaa/llamaup` in your environment (or `.bashrc`)
3. Enable GitHub Actions in your fork
4. Optionally trigger the first build manually from the Actions tab
5. Run `./scripts/pull.sh` on any of your machines

---

## Requirements

**For pulling:**
- `curl`, `jq`, `tar` (standard on most Linux distros)
- `nvidia-smi` (for auto-detection — not needed if you use `--sm`)

**Installing required tools:**
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y curl jq tar

# RHEL/CentOS/Fedora
sudo yum install -y curl jq tar

# Arch Linux
sudo pacman -S curl jq tar

# macOS (via Homebrew)
brew install curl jq
```

**For building locally:**
- `cmake >= 3.17`, `ninja`, `git`, `jq`
- CUDA toolkit with `nvcc`
- OpenSSL and libcurl development files (for HTTPS model downloads)

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y cmake ninja-build git jq libssl-dev libcurl4-openssl-dev

# RHEL/CentOS/Fedora
sudo yum install -y cmake ninja-build git jq openssl-devel libcurl-devel

# Arch Linux
sudo pacman -S cmake ninja git jq openssl
```

**For CI builds:**
- A GitHub account (free tier works — Actions minutes are consumed)
- No GPU hardware needed for the build runners

**Script permissions:**
- Scripts require execute permissions (`chmod +x scripts/*.sh`)
- Git clone preserves execute permissions automatically
- If you downloaded a ZIP archive, run `chmod +x scripts/*.sh` before use
- **Recommended permission: 755** (owner can write, all can execute)
- ⚠️ **Never use chmod 777** (security risk — allows anyone to modify scripts)

---

## Troubleshooting

### "HTTPS is not supported" error when using `-hf` flag

If you see this error:
```
HTTPS is not supported. Please rebuild with one of:
  -DLLAMA_BUILD_BORINGSSL=ON
  -DLLAMA_BUILD_LIBRESSL=ON
  -DLLAMA_OPENSSL=ON
```

**Cause:** You're using a binary built before HTTPS support was added (pre-Feb 2026 builds).

**Solutions:**

1. **Use a local model file** (workaround until new binaries are available):
   ```bash
   # Download model manually
   wget https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf
   
   # Run with local file
   llama-cli -m Qwen2.5-7B-Instruct-Q4_K_M.gguf -cnv -t 8
   ```

2. **Rebuild locally** (if you have sudo access):
   ```bash
   # Install dependencies
   sudo apt update && sudo apt install -y libssl-dev libcurl4-openssl-dev cmake ninja-build
   
   # Rebuild with HTTPS support
   ./scripts/build.sh --sm $(./scripts/detect.sh --json | jq -r '.gpus[0].sm')
   ```

3. **Google Colab users** - download models manually:
   ```bash
   # In a Colab cell
   !wget https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf -O model.gguf
   !llama-cli -m model.gguf -cnv
   ```

New binaries with HTTPS support will be available after the next CI run.

### GPU not detected or wrong SM version

Run the diagnostic tool:
```bash
./scripts/detect.sh --json
```

If your GPU is not in the output or has the wrong SM version, see [CONTRIBUTING.md](CONTRIBUTING.md) to add/fix the GPU mapping.

---

## Contributing

We welcome contributions! Whether you're fixing a GPU mapping, adding support for a new GPU, or improving the scripts, your help is appreciated.

**Quick links:**
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution guidelines (GPU mappings, binaries, code)
- [TESTING.md](TESTING.md) — Testing guide and development workflows
- [GPU_MATCHING.md](docs/GPU_MATCHING.md) — How GPU substring matching works

**Common contributions:**
- Update `configs/gpu_map.json` with new or corrected GPU entries
- Build and upload binaries for SM versions not yet in releases
- Improve documentation or fix typos
- Add test cases or improve existing scripts

Before submitting a PR:
1. Run `shellcheck scripts/*.sh` (must pass with zero warnings)
2. Run automated tests: `./scripts/test_gpu_matching.sh` and `./scripts/test_archive_integrity.sh`
3. Test on real hardware if possible
4. Update documentation as needed

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed instructions.

---

## License

MIT
