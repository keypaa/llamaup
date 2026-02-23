#!/usr/bin/env bash
# Test the list command with mock metadata

set -euo pipefail

# Source the script
source ./scripts/llama-models

echo "Creating test metadata in: $MODELS_DIR"
echo ""

# Ensure MODELS_DIR exists
mkdir -p "$MODELS_DIR"

# Model 1: Qwen2.5-Coder-1.5B-Instruct with multiple quantizations
MODEL1_DIR="${MODELS_DIR}/Qwen--Qwen2.5-Coder-1.5B-Instruct-GGUF"
mkdir -p "$MODEL1_DIR"

# Create fake GGUF files
dd if=/dev/zero of="${MODEL1_DIR}/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" bs=1M count=1 2>/dev/null
dd if=/dev/zero of="${MODEL1_DIR}/qwen2.5-coder-1.5b-instruct-q8_0.gguf" bs=1M count=2 2>/dev/null

# Save metadata for model 1
save_download_metadata \
  "$MODEL1_DIR" \
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF" \
  "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"

save_download_metadata \
  "$MODEL1_DIR" \
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF" \
  "qwen2.5-coder-1.5b-instruct-q8_0.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q8_0.gguf"

# Model 2: Llama-3-8B with different quantizations
MODEL2_DIR="${MODELS_DIR}/meta-llama--Meta-Llama-3-8B-Instruct-GGUF"
mkdir -p "$MODEL2_DIR"

dd if=/dev/zero of="${MODEL2_DIR}/Meta-Llama-3-8B-Instruct-Q5_K_M.gguf" bs=1M count=5 2>/dev/null
dd if=/dev/zero of="${MODEL2_DIR}/Meta-Llama-3-8B-Instruct-IQ4_XS.gguf" bs=1M count=4 2>/dev/null
dd if=/dev/zero of="${MODEL2_DIR}/Meta-Llama-3-8B-Instruct-Q2_K.gguf" bs=1M count=2 2>/dev/null

save_download_metadata \
  "$MODEL2_DIR" \
  "meta-llama/Meta-Llama-3-8B-Instruct-GGUF" \
  "Meta-Llama-3-8B-Instruct-Q5_K_M.gguf" \
  "https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q5_K_M.gguf"

save_download_metadata \
  "$MODEL2_DIR" \
  "meta-llama/Meta-Llama-3-8B-Instruct-GGUF" \
  "Meta-Llama-3-8B-Instruct-IQ4_XS.gguf" \
  "https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-IQ4_XS.gguf"

save_download_metadata \
  "$MODEL2_DIR" \
  "meta-llama/Meta-Llama-3-8B-Instruct-GGUF" \
  "Meta-Llama-3-8B-Instruct-Q2_K.gguf" \
  "https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q2_K.gguf"

echo ""
echo "Testing list_local_models()..."
echo ""
echo "══════════════════════════════════════════════════════════════════════════════"

# Call the list command
list_local_models

echo "══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Cleanup..."
rm -rf "$MODEL1_DIR"
rm -rf "$MODEL2_DIR"

echo "✓ Test complete"
