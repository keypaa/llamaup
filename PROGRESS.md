# llama-models Development Progress

**Last Updated**: February 22, 2026  
**Current Phase**: Phase 2 Complete ✅ → Ready for Phase 3

---

## Project Overview

`llama-models` is an optional TUI tool for browsing and downloading GGUF models from HuggingFace. It's part of the `llamaup` project which distributes pre-built llama.cpp CUDA binaries.

**Key Design Principles:**
- Zero-bloat: Premium dependencies (gum, aria2c) are **opt-in only**
- Dual-mode architecture: Premium (modern TUI) vs Minimal (bash-native fallback)
- Storage: `~/.local/share/llama-models`
- API: HuggingFace REST API (`https://huggingface.co/api/models`)

---

## ✅ Completed Work

### Phase 1: Foundation (Tasks 1-3) ✅

**Status**: COMPLETE  
**Files Created/Modified**:
- `scripts/llama-models` (370 lines, executable)
- `docs/LLAMA_MODELS.md` (development documentation)

**What was implemented**:

1. **Script skeleton** with proper bash conventions:
   - `set -euo pipefail` for strict error handling
   - Color output helpers (CYAN, GREEN, YELLOW, RED, etc.)
   - Logging functions: `info()`, `warn()`, `error()`, `success()` → all output to `stderr`
   - Version: v0.1.0
   - CLI: `--help`, `--version`, `--mode`, `--install-deps`, `search`, `list`

2. **Dependency detection** (`check_dependency()`):
   - POSIX-compliant detection using `command -v`
   - Checks for: `gum`, `aria2c`, `curl`, `jq`

3. **Mode selection** (`detect_mode()`):
   - Auto-detects if `gum` and `aria2c` are available
   - Sets `MODE=premium` or `MODE=minimal`
   - Can be overridden with `--mode` flag

4. **Installation system** (`install_dependencies()`):
   - Non-intrusive prompt: "Do you want to install premium dependencies? [y/N]"
   - Multi-platform support:
     - **Ubuntu/Debian**: `apt install aria2` + download gum binary
     - **RHEL/Fedora**: `yum install aria2` + gum binary
     - **Arch**: `pacman -S aria2` + gum binary
     - **macOS**: `brew install gum aria2`
   - Installs to `~/.local/bin` (user-local, no sudo for binaries)
   - Adds PATH warning if `~/.local/bin` not in PATH

5. **Directory structure**:
   - Models stored in: `~/.local/share/llama-models/`
   - Auto-creates on first run

**Testing**:
- ✅ `./scripts/llama-models --help` → Shows formatted help (colors working with `echo -e`)
- ✅ `./scripts/llama-models list` → Detects missing deps, offers installation
- ✅ Script has 755 permissions

**Key Fixes Applied**:
- Changed `usage()` from `cat <<EOF` to `echo -e` to fix ANSI escape codes display
- All logging functions output to `stderr` to avoid contaminating command output

---

### Phase 2: HuggingFace API Integration (Tasks 4-6) ✅

**Status**: COMPLETE  
**Files Created/Modified**:
- `scripts/llama-models` (API functions added)
- `test_api.sh` (test harness, working)

**What was implemented**:

1. **`search_models(query, limit)`** - HuggingFace API search:
   ```bash
   # Queries: https://huggingface.co/api/models
   # Parameters:
   #   - search=${query}
   #   - filter=gguf (only GGUF models)
   #   - sort=downloads&direction=-1 (most downloaded first)
   #   - full=true (CRITICAL: returns siblings array with file metadata)
   #   - limit=${limit}
   # Returns: JSON array of models
   ```
   - Uses `curl -fsSL --max-time 30`
   - Validates JSON with `jq empty`
   - Outputs to `stdout`, logs to `stderr`

2. **`filter_gguf_models(json)`** - Filter GGUF models:
   - Uses `jq` to filter models with `.gguf` files in siblings
   - Checks both tags and filenames
   - **Note**: With `filter=gguf` in API params, this is mostly redundant

3. **`parse_model_metadata(model_json)`** - Extract metadata:
   ```bash
   # Returns: id|downloads|size|quant_count
   # Example: "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|255511|17.2GiB|24"
   ```
   - Extracts: `.id`, `.downloads`
   - Counts GGUF files: `[.siblings[] | select(.rfilename | endswith(".gguf"))] | length`
   - Calculates total size: sum of all `.siblings[].size` for `.gguf` files
   - Formats size with `numfmt --to=iec-i --suffix=B` (fallback: awk)
   - Formats downloads with `numfmt --grouping` (adds thousands separators)

4. **`list_gguf_files(model_json)`** - List quantization variants:
   - Comprehensive quant detection regex in jq:
     - Full precision: `BF16`, `F16`, `F32`
     - K-quants: `Q8_0`, `Q6_K`, `Q5_K_M`, `Q5_K_S`, `Q4_K_M`, `Q4_K_S`, etc.
     - Legacy: `Q5_1`, `Q5_0`, `Q4_1`, `Q4_0`
     - IQuant: `IQ4_XS`, `IQ4_NL`, `IQ3_XXS`, `IQ3_XS`, `IQ2_XXS`, `IQ2_XS`, `IQ1_S`
     - MXFP: `MXFP4`
   - Returns JSON array: `[{filename, size, quant}]`

**Testing**:
- ✅ `./test_api.sh` → Successfully queries HF API, parses 3 models
- ✅ Output shows: model ID, downloads (formatted), GGUF count
- ✅ Example results:
  - `xtuner/llava-llama-3-8b-v1_1-gguf` - 467,432 downloads - 3 variants
  - `hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF` - 458,436 downloads - 1 variant
  - `bartowski/Meta-Llama-3.1-8B-Instruct-GGUF` - 255,511 downloads - 24 variants

**Critical Bugs Fixed**:

1. **API parameter issue**: Missing `full=true` → siblings array was empty
   - Fix: Added `full=true` to API params

2. **Logging contamination**: `info()` output captured in `$(search_models)` variable
   - Fix: All logging functions now output to `stderr` with `>&2`

3. **Process substitution issue**: `set -euo pipefail` + pipe subshell caused failures
   - Original (broken): `echo "$results" | jq -c '.[]' | while read -r model; do`
   - Fix: Use process substitution: `while read -r model; do ... done < <(echo "$results" | jq -c '.[]')`

4. **Size display issue**: API with `full=true` doesn't always include `size` field
   - Current behavior: Shows "0B" for some models
   - Future fix: Would need individual model API calls (`/api/models/{id}`) but slower

**API Knowledge Gained**:
- `/api/models?filter=gguf` → List endpoint, `full=true` adds siblings (but not all fields)
- `/api/models/{model_id}` → Individual model endpoint, has complete data including `gguf.total`
- `gguf.total` field only available on individual model queries, not list queries

---

## 📋 Todo List (14 Tasks Remaining)

### Phase 3: Minimal Mode Implementation (Tasks 7-9)
**Goal**: Bash-native fallback mode, zero dependencies beyond curl/jq

- [ ] **Task 7**: Implement minimal mode: bash `select` menu
  - `run_minimal_search()` function
  - Display search results with numbered list
  - Use bash built-in `select` for model selection
  - Show: ID, downloads, quant count

- [ ] **Task 8**: Minimal mode: paginated results display
  - Handle >10 results gracefully
  - "Show more" / "Next page" option
  - Limit default to 20 results

- [ ] **Task 9**: Minimal mode: curl download with progress
  - Reuse `download_file()` from `pull.sh` (tqdm-style progress bar)
  - Show: `45%|█████████░░░░░░░| 56.0M/124M`
  - Save to `~/.local/share/llama-models/{model_id}/{filename}`

### Phase 4: Premium Mode Implementation (Tasks 10-13)
**Goal**: Modern TUI experience with gum

- [ ] **Task 10**: Premium mode: auto-install gum + aria2c
  - Already implemented: `install_dependencies()`
  - Test on clean system

- [ ] **Task 11**: Premium mode: gum-based TUI interface
  - `run_premium_search()` function
  - Use `gum filter` for fuzzy search through results
  - Use `gum choose` for model selection
  - Show rich preview with `gum style`

- [ ] **Task 12**: Premium mode: quantization preview panel
  - When model selected, show all quants in table
  - Columns: Quant | Size | Label
  - Labels: "Best quality", "Balanced", "Fast", "Lossy" (see Task 14)
  - Use `gum choose --no-limit` for multi-select

- [ ] **Task 13**: Premium mode: aria2c download integration
  - Replace curl with aria2c for downloads
  - Multi-connection: `aria2c -x 16` (16 connections)
  - Show aria2c's built-in progress bar
  - Fallback to curl if aria2c fails

### Phase 5: Advanced Features (Tasks 14-17)

- [ ] **Task 14**: Quantization labels (best/good/fast/lossy)
  - Create `get_quant_label()` function
  - Mapping:
    - **Best**: F16, BF16, Q8_0
    - **Balanced**: Q6_K, Q5_K_M, Q5_0
    - **Fast**: Q4_K_M, Q4_0
    - **Lossy**: Q3_K_M, Q2_K, IQ3_XXS, IQ2_XXS
  - Color-code in output (Green=best, Yellow=balanced, Red=lossy)

- [ ] **Task 15**: Local storage in `~/.local/share/llama-models`
  - Already created directory structure
  - Organize by model ID: `{model_id}/{filename}`
  - Add metadata file: `{model_id}/metadata.json` with download date, source URL

- [ ] **Task 16**: SHA256 verification for downloads
  - HuggingFace API provides `.siblings[].lfs.sha256` (if available)
  - Download `.sha256` file from HF if exists
  - Verify with `sha256sum -c` or manual hash check
  - Reuse `verify.sh` logic from main llamaup

- [ ] **Task 17**: Resume interrupted downloads
  - curl: `curl -C -` (continue)
  - aria2c: built-in resume support
  - Check if partial file exists before download
  - Verify integrity after resume

### Phase 6: Documentation & Testing (Tasks 18-20)

- [ ] **Task 18**: Add llama-models docs to README.md
  - New section: "Optional: Model Browser"
  - Installation: `./scripts/llama-models --install-deps`
  - Usage examples
  - Link to `docs/LLAMA_MODELS.md`

- [ ] **Task 19**: Test minimal mode end-to-end
  - Uninstall gum + aria2c
  - Run full workflow: search → select → download
  - Verify file in `~/.local/share/llama-models/`

- [ ] **Task 20**: Test premium mode end-to-end
  - Install gum + aria2c
  - Run full workflow with TUI
  - Verify aria2c speed improvement
  - Test multi-select download

---

## 🏗️ Technical Decisions & Architecture

### File Structure
```
scripts/llama-models           # Main executable (currently 440 lines)
docs/LLAMA_MODELS.md           # Development documentation
test_api.sh                    # Phase 2 test harness
~/.local/share/llama-models/   # Model storage (created at runtime)
```

### Bash Best Practices Followed
- `set -euo pipefail` (strict mode)
- All functions documented with: purpose, args, return value, exit codes
- Color output only when stdout is TTY
- `SCRIPT_DIR` resolution: `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
- Logging to stderr: `info()`, `warn()`, `error()` use `>&2`
- Data to stdout: Functions return data via `echo`, not `return`

### Process Substitution Pattern (Important!)
```bash
# ❌ BROKEN: Subshell pipe issues with set -euo pipefail
echo "$results" | jq -c '.[]' | while read -r model; do
  ...
done

# ✅ CORRECT: Process substitution
while read -r model; do
  ...
done < <(echo "$results" | jq -c '.[]')
```

### API Usage Pattern
```bash
# 1. Search with full=true
results=$(search_models "llama" 20)

# 2. Validate
if [[ -z "$results" ]] || ! echo "$results" | jq empty 2>/dev/null; then
  error "Invalid API response"
fi

# 3. Iterate safely
while read -r model; do
  id=$(echo "$model" | jq -r '.id')
  # ... process model
done < <(echo "$results" | jq -c '.[]')
```

---

## 🐛 Known Issues & Limitations

1. **Size display shows "0B"**:
   - HF API `/models?full=true` doesn't include `size` field in siblings
   - Would need individual `/models/{id}` calls (slower)
   - For now: shows quant count instead

2. **No shard detection yet**:
   - Some models have split files: `model-00001-of-00003.gguf`
   - Should group shards and show total size
   - See reference implementation in user's `hf_gguf.sh` script

3. **No download functionality yet**:
   - Download URL: `https://huggingface.co/{model_id}/resolve/main/{filename}`
   - To be implemented in Phase 3/4

---

## 🚀 Next Steps (Phase 3)

**Immediate Priority**: Implement minimal mode search and selection

1. Create `run_minimal_search(query)`:
   ```bash
   run_minimal_search() {
     local query="$1"
     local results models
     
     results=$(search_models "$query" 20)
     
     # Display results with numbering
     echo "Search results for: $query"
     echo
     
     local i=1
     while read -r model; do
       local metadata
       metadata=$(parse_model_metadata "$model")
       IFS='|' read -r id downloads size quants <<< "$metadata"
       
       printf "%2d) %s\n" "$i" "$id"
       printf "    ↳ %s downloads, %s quants\n" "$downloads" "$quants"
       i=$((i + 1))
     done < <(echo "$results" | jq -c '.[]')
     
     # Bash select menu
     echo
     echo "Select a model to download (or 0 to cancel):"
     select choice in $(echo "$results" | jq -r '.[].id'); do
       if [[ -n "$choice" ]]; then
         download_model "$choice"
         break
       fi
     done
   }
   ```

2. Create `download_model(model_id)`:
   - Fetch individual model data: `curl "/api/models/${model_id}"`
   - List quants with `list_gguf_files()`
   - Use bash `select` to choose quant
   - Download with curl + progress bar

3. Test:
   ```bash
   ./scripts/llama-models search qwen
   # → Shows numbered list
   # → User selects model
   # → Shows quant options
   # → Downloads selected file
   ```

**Estimated Time**: 2-3 hours for Phase 3 complete

---

## 📝 References

- HuggingFace API docs: https://huggingface.co/docs/hub/api
- GGUF quantization guide: https://github.com/ggerganov/llama.cpp/blob/master/examples/quantize/README.md
- Gum TUI framework: https://github.com/charmbracelet/gum
- aria2c docs: https://aria2.github.io/manual/en/html/

---

## 📞 Continuation Instructions

If you lose this chat, here's how to continue:

1. **Check current state**:
   ```bash
   cd /teamspace/studios/this_studio/llamaup
   ./scripts/llama-models --help   # Should work
   ./test_api.sh                   # Should query API successfully
   ```

2. **Read this file**: `cat PROGRESS.md`

3. **Start Phase 3**: Implement `run_minimal_search()` in `scripts/llama-models`

4. **Key context**:
   - All logging → stderr (`>&2`)
   - Use process substitution for loops: `while read; do ... done < <(...)`
   - API needs `full=true` parameter
   - Test with: `./scripts/llama-models search llama`

Good luck! 🚀
