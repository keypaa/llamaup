#!/usr/bin/env bash
# install.sh — Bootstrap llamaup and pull the right binary for this machine.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/keypaa/llamaup/main/install.sh | bash
#   # or, after cloning:
#   ./install.sh
set -euo pipefail

REPO="${LLAMAUP_REPO:-keypaa/llamaup}"
BRANCH="${LLAMAUP_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# If we're inside a cloned repo, use local scripts; otherwise download them.
if [[ -f "./scripts/pull.sh" ]]; then
  SCRIPTS_DIR="./scripts"
else
  # Mirror the repo layout (root/scripts + root/configs) so the scripts can
  # resolve ../configs/gpu_map.json relative to their own directory.
  ROOT_DIR="$(mktemp -d)"
  trap 'rm -rf "$ROOT_DIR"' EXIT
  SCRIPTS_DIR="${ROOT_DIR}/scripts"
  CONFIGS_DIR="${ROOT_DIR}/configs"
  mkdir -p "$SCRIPTS_DIR" "$CONFIGS_DIR"
  for f in detect.sh pull.sh verify.sh list.sh; do
    curl -fsSL "${RAW}/scripts/${f}" -o "${SCRIPTS_DIR}/${f}"
  done
  curl -fsSL "${RAW}/configs/gpu_map.json" -o "${CONFIGS_DIR}/gpu_map.json"
  chmod +x "${SCRIPTS_DIR}"/*.sh
fi

# Ensure ~/.local/bin is on PATH for this session.
export PATH="${HOME}/.local/bin:${PATH}"

exec "${SCRIPTS_DIR}/pull.sh" "$@"
