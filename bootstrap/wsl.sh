#!/usr/bin/env bash
# Phase 0 bootstrap — WSL2 (Ubuntu/Debian inside Windows).
# Goal: get git, ansible and chezmoi available via apt.
# Sourced by install.sh / `rocket bootstrap`.
set -euo pipefail

logn "Updating apt cache:"; sudo apt-get update -qq; logk

logn "Installing base packages (git, python3, ansible):"
sudo apt-get install -y -qq git python3 python3-pip ansible curl >/dev/null
logk

# chezmoi is not reliably packaged in apt — use the official installer.
if ! command -v chezmoi >/dev/null 2>&1; then
  logn "Installing chezmoi:"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
  logk
fi

# Persist ~/.local/bin for new shells (chezmoi + the `rocket` symlink live there).
logn "Persisting ~/.local/bin to shell profile:"
rl_append_once "$HOME/.bashrc" "# rocket-launch (PATH)" 'export PATH="$HOME/.local/bin:$PATH"'
logk
