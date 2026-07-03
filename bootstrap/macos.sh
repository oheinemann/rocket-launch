#!/usr/bin/env bash
# Phase 0 bootstrap — macOS.
# Goal: get Command Line Tools, Homebrew, ansible and chezmoi available.
# Sourced by install.sh / `rocket bootstrap` (RL_* and log helpers are in scope).
set -euo pipefail

# --- Xcode Command Line Tools (headless, avoids the fragile GUI prompt) ---
install_clt() {
  if xcode-select -p >/dev/null 2>&1; then logn "Command Line Tools:"; logk; return; fi
  log "Installing Command Line Tools (headless)"
  # Trick: this placeholder makes `softwareupdate` list the CLT package.
  local flag="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "$flag"
  local label
  label="$(softwareupdate -l 2>/dev/null \
    | grep -E 'Command Line Tools' | tail -n1 \
    | sed -E 's/^[^C]*Label: //;s/^[ *]*//' )"
  if [ -n "$label" ]; then
    softwareupdate -i "$label" --verbose || true
  else
    warn "Could not find CLT via softwareupdate — falling back to GUI prompt."
    xcode-select --install || true
  fi
  rm -f "$flag"
}

# --- sudo priming ---
# Homebrew's NONINTERACTIVE installer needs sudo up front but cannot prompt when
# we run via `curl | bash`. Prime the sudo credential cache here (prompting on the
# terminal via /dev/tty) so the installer's `sudo -n` check passes.
ensure_sudo() {
  if sudo -n true 2>/dev/null; then return; fi   # passwordless or already cached
  log "Administrator rights are required (Homebrew install)."
  echo "    Enter your macOS login password:"
  sudo -v < /dev/tty || abort \
    "Need Administrator (sudo) access. In System Settings → Users & Groups, make '$USER' an Administrator, then re-run."
}

# --- Homebrew ---
install_brew() {
  if command -v brew >/dev/null 2>&1; then logn "Homebrew:"; logk; return; fi
  ensure_sudo
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon installs to /opt/homebrew; make brew available now.
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if [ -x /usr/local/bin/brew ];  then eval "$(/usr/local/bin/brew shellenv)"; fi
}

# --- Provisioners ---
install_provisioners() {
  logn "Installing git, ansible, chezmoi via brew:"
  brew install git ansible chezmoi >/dev/null
  logk
}

install_clt
install_brew
install_provisioners
