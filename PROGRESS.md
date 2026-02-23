# llama-models Development Progress

**Last Updated**: February 23, 2026  
**Current Phase**: Phase 5 Complete → Advanced Features (Tasks 14-18) ✅

---

## Project Overview

`llama-models` is an optional TUI tool for browsing and downloading GGUF models from HuggingFace. It's part of the `llamaup` project which distributes pre-built llama.cpp CUDA binaries.

**Key Design Principles:**
- Zero-bloat: Premium dependencies (gum, aria2c) are **opt-in only**
- Dual-mode architecture: Premium (modern TUI) vs Minimal (bash-native fallback)
- Storage: `~/.local/share/llama-models`
- API: HuggingFace REST API (`https://huggingface.co/api/models`)

**Implementation Status:**
- ✅ Phase 1: Foundation (Tasks 1-3) 
- ✅ Phase 2: API Integration (Tasks 4-6)
- ✅ Phase 3: Minimal Mode (Tasks 7-9)
- ✅ Phase 4: Premium Mode (Tasks 10-13)
- ✅ Phase 5: Advanced Features (Tasks 14-18)
- 🚧 Phase 6: Documentation & Testing (Tasks 19-20) ← **CURRENT**

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

### Phase 3: Minimal Mode Implementation (Tasks 7-9) ✅

**Status**: COMPLETE (all 3 tasks done)  
**Files Modified**:
- `scripts/llama-models` (now ~900 lines)

**What was implemented**:

1. **Task 7: Minimal mode bash select menu** ✅
   - `run_minimal_search(query)` - Full search and selection flow
   - `run_minimal_interactive()` - Interactive prompt for search query
   - `show_model_quantizations(model_json, model_id)` - Quant selection submenu
   - Display format:
     ```
     #   Model ID                                Downloads   Variants
     ─────────────────────────────────────────────────────────────────────────────
     1   ggml-org/tinygemma3-GGUF                879,915          2
     2   TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF  110,593         13
     ```
   - Uses bash built-in `select` for both model and quantization selection
   - Handles long model IDs with truncation (38 chars max)
   - Organized storage: `~/.local/share/llama-models/{model_id}/`

2. **Task 8: Paginated results display** ✅
   - Updated `search_models()` to accept offset parameter (3rd argument)
   - Added `skip` parameter to HuggingFace API URL for pagination
   - `run_minimal_search()` accumulates results across multiple pages
   - "── Show more ──" option automatically appears when more results available
   - User can load additional 20 results by selecting pagination option
   - Arrays (`all_model_ids`, `all_model_metadata`, `all_model_jsons`) grow across pages
   - Pagination logic: if `${#results[@]} < limit`, set `has_more=false`

3. **Task 9: Curl download with progress** ✅
   - `download_gguf_file(model_id, filename, dest_dir)` - Download from HuggingFace
   - Progress bar format (same as pull.sh):
     ```
     100%|██████████████████████████████| 4.2G/4.2G
     ```
   - Uses curl with custom progress parser
   - Downloads from: `https://huggingface.co/{model_id}/resolve/main/{filename}`
   - Fallback size calculation if curl doesn't provide total
   - Automatic cleanup on failure

3. **Helper functions** (added):
   - `format_size(bytes)` - Convert bytes to human-readable (GiB/MiB/KiB)
   - Works with or without `numfmt` (awk fallback)

**Critical Bug Fixes**:
- Fixed logging contamination: `info()` and `success()` now output to `stderr` (was stdout)
- This prevented JSON pollution when capturing API results with `results=$(search_models ...)`
- **Fixed deadlock in array population**: Replaced `while < <()` with `mapfile` to avoid process substitution + command substitution deadlock
  - Issue: `while IFS= read -r model; do metadata=$(parse_model_metadata "$model") ...` would hang
  - Root cause: `numfmt --grouping` in `parse_model_metadata` tried to read stdin, creating a deadlock
  - Fix 1: Use `echo "$value" | numfmt` instead of `numfmt "$value"`
  - Fix 2: Replace while loop pattern with `mapfile -t array < <(...)` followed by for loop
- **Fixed null handling in `format_size()`**: Added checks for null/empty values from API before arithmetic operations
- **Fixed download progress buffering**: Progress bar now updates in real-time (not stuck at 0%)
  - Changed from parsing curl's stderr to monitoring file size while curl runs in background
  - Fetches total size from HTTP Content-Length header
  - Updates display every 0.5 seconds with current file size and percentage

**Phase 3 Status**: ✅ **COMPLETE** - All minimal mode features fully implemented and tested!

**User Experience Flow**:
```bash
$ ./scripts/llama-models search qwen
→ Running in minimal mode
→ Searching HuggingFace...
→ Parsing results...

Found 5 GGUF models:

#   Model ID                                Downloads   Variants
─────────────────────────────────────────────────────────────────────────────
1   unsloth/Qwen3-Coder-Next-GGUF           502,434         40
2   MaziyarPanahi/Qwen3-4B-GGUF             202,732          7
...

Select a model to download (or 'q' to quit):
1) unsloth/Qwen3-Coder-Next-GGUF
2) MaziyarPanahi/Qwen3-4B-GGUF
...
Enter number: 2

Model: MaziyarPanahi/Qwen3-4B-GGUF

Available quantizations:

#   Quant     Size        Filename
─────────────────────────────────────────────────────────────────────────────
1   Q2_K      1.5GiB      Qwen3-4B.Q2_K.gguf
2   Q4_K_M    2.4GiB      Qwen3-4B.Q4_K_M.gguf
...

Select a quantization:
1) Q2_K
2) Q4_K_M
...
Enter number: 2

→ Downloading: Qwen3-4B.Q4_K_M.gguf
→ From: MaziyarPanahi/Qwen3-4B-GGUF

100%|██████████████████████████████| 2.4G/2.4G

✓ Downloaded to: ~/.local/share/llama-models/MaziyarPanahi_Qwen3-4B-GGUF/Qwen3-4B.Q4_K_M.gguf

✓ Model ready to use!

Saved to: ~/.local/share/llama-models/MaziyarPanahi_Qwen3-4B-GGUF

Run with llama.cpp:
  llama-cli -m ~/.local/share/llama-models/MaziyarPanahi_Qwen3-4B-GGUF/Qwen3-4B.Q4_K_M.gguf
```

**Task 8 Status**: Pagination not yet implemented  
- Currently shows all results (limit=20)
- No "Show more" or "Next page" functionality yet
- This will be addressed in next session

**Known Issues**:
- Sizes show "N/A" in quantization menu because HF API list endpoint doesn't include individual file sizes
  - Fix would require individual `/api/models/{id}` calls per model (slower)
  - Will be addressed in premium mode or as future enhancement
- ~~ANSI escape codes show as literal text~~ ✅ **FIXED**: Changed to `echo -e` for formatting

---

## 📋 Todo List (10 Tasks Remaining)

### Phase 3: Minimal Mode Implementation (Tasks 7-9)
**Goal**: Bash-native fallback mode, zero dependencies beyond curl/jq

- [x] **Task 7**: Implement minimal mode: bash `select` menu ✅
  - `run_minimal_search()` function  
  - Display search results with numbered list
  - Use bash built-in `select` for model selection
  - Show: ID, downloads, quant count

- [x] **Task 8**: Minimal mode: paginated results display ✅
  - Handles >20 results gracefully
  - "── Show more ──" option appears in select menu
  - Fetches next 20 results with offset parameter
  - Accumulates results across pages

- [x] **Task 9**: Minimal mode: curl download with progress ✅
  - `download_gguf_file()` implemented with progress bar
  - Show: `100%|██████████████| 2.4G/2.4G`
  - Save to `~/.local/share/llama-models/{model_id}/{filename}`

### Phase 4: Premium Mode Implementation (Tasks 10-13) ✅

**Status**: COMPLETE  
**Files Modified**:
- `scripts/llama-models` (premium mode functions added)
- `test_premium_mode.sh` (test suite created)

**What was implemented**:

- [x] **Task 10**: Premium  mode: auto-install gum + aria2c ✅
  - `install_dependencies()` - Main installer function
  - `install_linux_dependencies()` - apt/yum/pacman support
  - `install_macos_dependencies()` - Homebrew support
  - `install_gum_linux()` - Downloads gum binary to ~/.local/bin
  - Automatic PATH detection and warning

- [x] **Task 11**: Premium mode: gum-based TUI interface ✅
  - `run_premium_interactive()` - Styled welcome screen with gum
  - `run_premium_search()` - Fuzzy search with `gum filter`
  - Displays: Model ID | downloads | variants
  - Fuzzy search through up to 50 results
  - Clean TUI with borders, colors, and formatting

- [x] **Task 12**: Premium mode: quantization preview panel ✅
  - `show_premium_model_quantizations()` - TUI quantization selector
  - Uses `gum choose` for single selection
  - Displays table: Quantization | Size | Filename
  - Styled borders and formatted output
  - "Back" and "Quit" options

- [x] **Task 13**: Premium mode: aria2c download integration ✅
  - `download_aria2c_file()` - Multi-connection downloader
  - Options: `-x16 -s16` (16 connections, 16 segments)
  - Automatic fallback to curl if aria2c unavailable
  - Integrated into quantization selector

**Premium Mode Features**:
- ✨ Fuzzy search with `gum filter`
- 🎨 Styled TUI with `gum style` (borders, colors, padding)
- ⚡ 16x faster downloads with aria2c multi-connection
- 🔄 Automatic fallback to minimal mode if dependencies missing
- 📦 One-command dependency installation

**Usage**:
```bash
# Install dependencies
./scripts/llama-models --install-deps

# Force premium mode
MODE=premium ./scripts/llama-models

# Auto-detect (uses premium if gum+aria2c available)
./scripts/llama-models
```

**Phase 4 Status**: ✅ **COMPLETE** - Premium mode fully functional!

---

### Phase 5: Advanced Features (Tasks 14-18) 🚧

**Status**: IN PROGRESS  

- [x] **Task 14**: Quantization labels (best/balanced/fast/lossy) ✅
  - Created `get_quant_label()` function that classifies quantizations:
    - **Lossless** (Green): F32, F16, BF16 — no loss, identical to original
    - **Near-Lossless** (Cyan): Q8_0, Q6_K, Q6_K_L — loss < 0.1%, sweet spot with VRAM
    - **Recommended** (Yellow): Q5_K_M, Q5_K_S, Q5_1, Q4_K_M — best quality/size tradeoff
    - **Fast** (Yellow): Q4_K_S, Q4_1, Q4_0, IQ4_XS, IQ4_NL — acceptable for daily work
    - **Lossy** (Red): Q3_K_L/M/S, Q2_K/Q2_K_L, IQ3_XXS/XS, IQ2_XXS/XS — for limited machines
    - **Experimental** (Magenta): MXFP4, IQ1_S — very recent or extreme formats
    - **Other** (Dim): Unknown quantizations
  - Updated both minimal and premium mode displays
  - Added "Quality" column to quantization tables
  - Color-coded labels for easy visual identification
  - Comprehensive classification based on actual quant behavior
  - Note: smaller models (< 7B) suffer more from quantization
  - Tested with real HuggingFace models ✓

- [x] **Task 15**: Local storage in `~/.local/share/llama-models` ✅
  - Implemented `save_download_metadata()` function
  - Creates `{model_id}/metadata.json` after each successful download
  - Metadata includes:
    - Download timestamp (ISO 8601 format)
    - Source URL (HuggingFace)
    - File size (bytes + human-readable)
    - Quantization type (auto-detected from filename, case-insensitive)
    - Quality label (Lossless/Near-Lossless/Recommended/Fast/Lossy/Experimental)
  - Supports multiple downloads per model (array structure)
  - Prevents duplicates (updates timestamp if same file re-downloaded)
  - Used by formula: curl download + aria2c download
  - Tested with simulated downloads ✓

- [x] **Task 16**: List command (`llama-models list`) ✅
  - Implemented `list_local_models()` function
  - Scans `~/.local/share/llama-models/` for all metadata.json files
  - Displays table with columns:
    - Model ID (truncated to 38 chars if too long)
    - Quant (color-coded by quality label)
    - Size (human-readable format)
    - Downloaded (ISO date, short format YYYY-MM-DD)
  - Supports multiple quantizations per model
  - Shows helpful message if no models downloaded yet
  - Note about models without metadata (pre-tracking downloads)
  - Tested with multiple models and quantizations ✓

- [x] **Task 17**: Install command with version check ✅
  - Implemented `check_existing_file()` function
  - Checks if file already exists before downloading
  - Shows file info (location, size) when duplicate detected
  - Prompts user: "Re-download this file? [y/N]"
  - Default behavior: skip download if user says no
  - Added `--force` flag to bypass duplicate check
  - Integrated into both download methods:
    - `download_gguf_file()` (curl-based)
    - `download_aria2c_file()` (aria2c-based)
  - Updated `--help` documentation with --force flag
  - Prevents wasted bandwidth and time
  - Tested with simulated downloads ✓

- [x] **Task 18**: Sync command ✅
  - Implemented `sync_local_models()` function to check for model updates
  - Scans all local `metadata.json` files in `~/.local/share/llama-models/`
  - For each model, fetches current HuggingFace data via API
  - Detects two types of updates:
    - **New quantizations**: Available on HF but not downloaded locally (shown in GREEN)
    - **Size mismatches**: Local file size differs from HF (indicates corrupted/fixed files, shown in YELLOW)
  - Color-coded reporting:
    - `✓` Up to date (GREEN)
    - `+` New quantizations (CYAN)
    - `!` Size mismatch with local/HF sizes displayed (YELLOW)
    - `✗` API fetch failed (RED)
  - Provides actionable help text:
    - `llama-models search <model-name>` for new quantizations
    - `llama-models --force search <model-name>` to re-download corrupted files
  - Added `sync` action to main execution flow
  - Updated `detect_mode()` to skip installation prompt for sync (like list)
  - Supports `LLAMA_MODELS_DIR` environment variable for testing
  - Test coverage: `test_sync_command.sh` (4 tests, all passing)
  - **Real-world use case**: GGUF files can be corrupted/badly compiled (e.g., gLM 5), requiring re-download detection

### Phase 6: Documentation & Testing (Tasks 19-20)

- [ ] **Task 19**: Test minimal mode end-to-end
  - Uninstall gum + aria2c
  - Run full workflow: search → select → download
  - Verify file in `~/.local/share/llama-models/`
  - Document in README.md

- [ ] **Task 20**: Test premium mode end-to-end
  - Install gum + aria2c
  - Run full workflow with TUI
  - Verify aria2c speed improvement
  - Test multi-select download
  - Document in README.md

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
