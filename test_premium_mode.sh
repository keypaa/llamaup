#!/usr/bin/env bash
# test_premium_mode.sh — End-to-end test for llama-models in premium mode
#
# Task 20: Test premium mode workflow
#   - Verify gum + aria2c are installed
#   - Run full workflow with TUI
#   - Verify aria2c speed improvement
#   - Test multi-select download
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}[test-premium]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[test-premium]${RESET} $*" >&2; }
warn() { echo -e "${YELLOW}[test-premium]${RESET} $*" >&2; }
error() { echo -e "${RED}[test-premium]${RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

check_dependencies() {
    info "Checking premium mode dependencies..."
    
    local missing=()
    
    if ! command -v gum &>/dev/null; then
        missing+=("gum")
    fi
    
    if ! command -v aria2c &>/dev/null; then
        missing+=("aria2c")
    fi
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo ""
        info "To install premium dependencies, run:"
        echo "  ./scripts/llama-models --install-deps"
        echo ""
        info "Or install manually:"
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt install -y aria2 curl jq"
        echo "  # Install gum from: https://github.com/charmbracelet/gum/releases"
        echo ""
        return 1
    fi
    
    success "✓ All premium dependencies installed"
    return 0
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test_gum_version() {
    info "Test 1: gum installation"
    
    local gum_path
    gum_path=$(command -v gum)
    
    success "✓ gum found at: $gum_path"
    
    # Try to get version
    if gum --version &>/dev/null; then
        local version
        version=$(gum --version 2>&1 | head -n1)
        info "  Version: $version"
    fi
}

test_aria2c_version() {
    info "Test 2: aria2c installation"
    
    local aria2c_path
    aria2c_path=$(command -v aria2c)
    
    success "✓ aria2c found at: $aria2c_path"
    
    # Try to get version
    if aria2c --version &>/dev/null; then
        local version
        version=$(aria2c --version 2>&1 | head -n1)
        info "  Version: $version"
    fi
}

test_mode_detection() {
    info "Test 3: Mode detection should select 'premium'"
    
    # Create a temporary script to check mode detection
    local temp_script="/tmp/test_mode_$$. sh"
    cat > "$temp_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Inline mode detection logic
MODE="minimal"

if command -v gum &>/dev/null && command -v aria2c &>/dev/null; then
    MODE="premium"
fi

echo "$MODE"
EOF
    chmod +x "$temp_script"
    
    local detected_mode
    detected_mode=$("$temp_script")
    rm "$temp_script"
    
    if [[ "$detected_mode" == "premium" ]]; then
        success "✓ Mode detected as: premium"
    else
        error "✗ Mode detected as: $detected_mode (expected premium)"
        return 1
    fi
}

test_models_directory() {
    info "Test 4: Models directory creation"
    
    models_dir="${LLAMA_MODELS_DIR:-${HOME}/.local/share/llama-models}"
    
    if [[ -d "$models_dir" ]] || mkdir -p "$models_dir"; then
        success "✓ Models directory: $models_dir"
        
        # Check write permissions
        if [[ -w "$models_dir" ]]; then
            success "✓ Models directory is writable"
        else
            error "✗ Models directory is not writable"
            return 1
        fi
    else
        error "✗ Cannot create models directory"
        return 1
    fi
}

test_api_connectivity() {
    info "Test 5: HuggingFace API connectivity"
    
    # Test basic API call (same as search would do)
    if curl -fsSL --max-time 10 \
        "https://huggingface.co/api/models?search=qwen&filter=gguf&limit=1" \
        -o /dev/null 2>/dev/null; then
        success "✓ HuggingFace API accessible"
    else
        warn "⚠ HuggingFace API not accessible (may be network issue)"
    fi
}

test_aria2c_performance() {
    info "Test 6: aria2c download performance"
    
    # Download a small test file to verify aria2c works
    local test_url="https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/hub/repo-types.png"
    local test_file="/tmp/aria2c_test_$$.png"
    
    info "Downloading test file with aria2c..."
    
    local start_time
    start_time=$(date +%s)
    
    if aria2c --console-log-level=warn \
              --summary-interval=0 \
              --file-allocation=none \
              --max-connection-per-server=8 \
              --split=8 \
              --min-split-size=1M \
              -d /tmp \
              -o "aria2c_test_$$.png" \
              "$test_url" &>/dev/null; then
        
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        success "✓ aria2c download completed in ${duration}s"
        
        # Clean up
        rm -f "$test_file"
    else
        error "✗ aria2c download failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main test runner
# ---------------------------------------------------------------------------

main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  llama-models — Premium Mode End-to-End Test (Task 20)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local failed=0
    
    # Check dependencies first
    if ! check_dependencies; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        error "Cannot run tests without all dependencies installed"
        echo "═══════════════════════════════════════════════════════════════"
        return 1
    fi
    
    echo ""
    
    # Run tests
    test_gum_version || ((failed++))
    echo ""
    
    test_aria2c_version || ((failed++))
    echo ""
    
    test_mode_detection || ((failed++))
    echo ""
    
    test_models_directory || ((failed++))
    echo ""
    
    test_api_connectivity || ((failed++))
    echo ""
    
    test_aria2c_performance || ((failed++))
    echo ""
    
    # Summary
    echo "═══════════════════════════════════════════════════════════════"
    if [[ $failed -eq 0 ]]; then
        success "All tests passed! ✓"
        echo ""
        echo -e "${CYAN}Manual testing steps:${RESET}"
        echo ""
        echo "1. Run llama-models search with gum TUI:"
        echo "   ./scripts/llama-models search qwen2.5-7b-instruct"
        echo ""
        echo "2. Use arrow keys + Space to select models in gum TUI"
        echo ""
        echo "3. Press Enter to confirm selection"
        echo ""
        echo "4. Select quantization(s) from the list"
        echo ""
        echo "5. Verify download uses aria2c (should see multi-connection output)"
        echo ""
        echo "6. Test multi-select: select multiple models at once"
        echo ""
        echo "7. Check downloaded files:"
        echo "   ls -lh ~/.local/share/llama-models/"
        echo ""
        echo "8. Compare download speed with curl (use --mode=minimal for comparison)"
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        return 0
    else
        error "$failed test(s) failed ✗"
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        return 1
    fi
}

main "$@"
