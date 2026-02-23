#!/usr/bin/env bash
# Quick test of download progress fix
set -euo pipefail

echo "Testing download progress in real-time..."
echo
echo "This will download a small GGUF file and show progress updates."
echo "You should see the percentage increasing gradually (not stuck at 0%)."
echo
echo "Press Ctrl+C within 5 seconds to cancel, or wait to continue..."
sleep 5

# Source the llama-models script to get the download function
source ./scripts/llama-models 2>/dev/null || {
  echo "Error: Could not source scripts/llama-models"
  exit 1
}

# Test with a small model
echo "Testing with a small model file..."
echo

# Create temp directory
test_dir="/tmp/llamaup-download-test-$$"
mkdir -p "$test_dir"

# Download a small file (should complete quickly but show progress)
# Using TinyLlama Q2_K which is relatively small
download_gguf_file \
  "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF" \
  "tinyllama-1.1b-chat-v1.0.Q2_K.gguf" \
  "$test_dir"

echo
echo "Test complete! Check if you saw incremental progress above."
echo "Cleaning up..."
rm -rf "$test_dir"
echo "Done!"
