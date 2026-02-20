# llamaup

**Pre-built Linux CUDA binaries for [llama.cpp](https://github.com/ggerganov/llama.cpp), organized by GPU architecture.**

No more compiling on every machine. Build once per SM version, store the binary, pull it anywhere in seconds.

---

## The problem

The official llama.cpp releases ship pre-built Windows CUDA binaries but **nothing for Linux CUDA**. If you're running llama.cpp on Linux across multiple GPU types (T4, A100, L40S, RTX 4090, H100...) you have to compile from source every time — on every machine, for every new release.

## The solution

This repo gives you:

- **`scripts/build.sh`** — builds llama.cpp for a specific GPU SM version and uploads the binary to GitHub Releases
- **`scripts/pull.sh`** — detects your GPU, downloads the right pre-built binary, and installs it
- **`configs/gpu_map.json`** — maps GPU model names → SM versions
- **`.github/workflows/build.yml`** — CI pipeline that auto-builds all SM versions on new llama.cpp releases

---

## Quick start

### On a machine where you want to run llama.cpp

```bash
git clone https://github.com/keypaa/llamaup
cd llamaup

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
  llama-b4102-linux-cuda12.4-sm89-x64.tar.gz   ← for 4090, L40S
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

**For building locally:**
- `cmake >= 3.17`, `ninja`, `git`, `jq`
- CUDA toolkit with `nvcc`
- OpenSSL development files (for HTTPS model downloads)
  - Ubuntu/Debian: `sudo apt install libssl-dev`
  - RHEL/CentOS: `sudo yum install openssl-devel`

**For CI builds:**
- A GitHub account (free tier works — Actions minutes are consumed)
- No GPU hardware needed for the build runners

---

## Contributing

GPU map out of date? New SM version missing? PRs to `configs/gpu_map.json` are welcome.

---

## License

MIT
