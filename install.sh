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
  SCRIPTS_DIR="$(mktemp -d)"
  trap 'rm -rf "$SCRIPTS_DIR"' EXIT
  mkdir -p "$SCRIPTS_DIR"
  for f in detect.sh pull.sh verify.sh list.sh; do
    curl -fsSL "${RAW}/scripts/${f}" -o "${SCRIPTS_DIR}/${f}"
  done
  chmod +x "${SCRIPTS_DIR}"/*.sh
fi

# Ensure ~/.local/bin is on PATH for this session.
export PATH="${HOME}/.local/bin:${PATH}"

exec "${SCRIPTS_DIR}/pull.sh" "$@"
