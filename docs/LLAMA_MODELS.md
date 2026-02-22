# llama-models — Development Documentation

## Overview

`llama-models` is an optional TUI tool for browsing and downloading GGUF models from HuggingFace. It's designed to be **lightweight and opt-in**, with zero required dependencies beyond what llamaup already needs.

## Architecture

### Two-Mode Design

**Premium Mode** (opt-in):
- Dependencies: `gum` + `aria2c`
- Modern TUI with fuzzy search
- Ultra-fast downloads (16 parallel connections)
- Best UX, but requires installation

**Minimal Mode** (fallback):
- Dependencies: none (bash native + curl)
- Simple bash `select` menu
- Standard curl downloads
- Works out-of-the-box on any system

### Why Two Modes?

1. **Zero bloat**: llamaup remains ultra-lightweight
2. **Graceful degradation**: Works even without extra tools
3. **Respect user choice**: Premium mode is opt-in, not forced
4. **Better UX path**: Easy upgrade to premium when ready

## Phase 1: Foundations ✅

**Status**: COMPLETED

### Implementation Details

#### 1. Script Skeleton (`scripts/llama-models`)

Created a complete foundation with:
- Proper shebang and `set -euo pipefail`
- Color constants (disabled in non-TTY)
- Helper functions (error, info, success, warn)
- Usage/help system
- Configuration constants

**Key decisions**:
- Models stored in `~/.local/share/llama-models` (XDG-compliant)
- Version tracking for future upgrades
- Sourceable script (can be imported by other tools)

#### 2. Dependency Detection

**Function**: `check_dependency()`
- Uses `command -v` (POSIX-compliant)
- Returns 0 if found, 1 if not
- Silent (no output unless error)

**Function**: `detect_mode()`
- Auto-detects gum and aria2c
- Sets global `MODE` variable
- Falls back gracefully if dependencies missing

**Testing**:
```bash
# Test dependency detection
./scripts/llama-models --help  # Works immediately
./scripts/llama-models list    # Prompts for installation if gum/aria2c missing
```

#### 3. Mode Selection

**Automatic selection**:
- Both `gum` + `aria2c` present → Premium mode
- Either missing → Offer installation
- User declines → Minimal mode

**Manual override**:
```bash
./scripts/llama-models --mode minimal    # Force minimal
./scripts/llama-models --mode premium    # Force premium (fails if deps missing)
```

**Installation prompt**:
- Clear, non-intrusive
- Explains benefits of premium mode
- Provides manual installation option
- Falls back gracefully on decline

### Installation System

**Function**: `install_dependencies()`
- Detects OS (Linux vs macOS)
- Uses native package managers
- Downloads gum binary directly (no package manager needed)

**Supported platforms**:
- ✅ Ubuntu/Debian (apt)
- ✅ RHEL/CentOS/Fedora (yum)
- ✅ Arch Linux (pacman)
- ✅ macOS (Homebrew)

**gum installation**:
- Downloads from official GitHub releases
- Detects x86_64 vs arm64
- Installs to `~/.local/bin`
- Preserves user's choice (no sudo needed)

**aria2c installation**:
- Uses system package manager
- Available in all major repos
- Requires sudo (standard package)

### File Structure

```
llamaup/
├── scripts/
│   └── llama-models          ← Main script (370 lines)
└── docs/
    └── LLAMA_MODELS.md       ← This file
```

### Configuration

```bash
# Storage location
MODELS_DIR="${HOME}/.local/share/llama-models"

# HuggingFace API
HF_API_URL="https://huggingface.co/api/models"

# Version
VERSION="0.1.0"
```

### Testing Results

```bash
# ✅ Help system works
./scripts/llama-models --help

# ✅ Dependency detection works
./scripts/llama-models list
# Output: Prompts for installation (gum/aria2c not installed)

# ✅ Version display works
./scripts/llama-models --version
# Output: llama-models v0.1.0

# ✅ Creates storage directory
ls ~/.local/share/
# Output: llama-models/ directory created
```

### Code Quality

- ✅ All functions documented with comment blocks
- ✅ Error handling with `set -euo pipefail`
- ✅ Graceful degradation (no hard failures)
- ✅ POSIX-compliant where possible
- ✅ Color-aware (disabled in non-TTY)

## Next Steps: Phase 2

**Goal**: HuggingFace API Integration

Tasks:
1. Build search function using HF API
2. Filter for GGUF models only
3. Parse model metadata (size, quantizations, downloads)

**API Endpoint**: `https://huggingface.co/api/models?search=<query>&filter=gguf`

**Expected output**: JSON list of models with metadata

---

**Last updated**: 2026-02-22
**Phase**: 1/6 (COMPLETED)
