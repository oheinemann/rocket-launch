#!/usr/bin/env bash
#
# rocket-launch — POSIX entry point (macOS / Linux / WSL2).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.sh | bash
#
# With a custom (private) config repo:
#   curl -fsSL .../install.sh | bash -s -- --config git@github.com:you/rocket-launch-config.git
#
# Flow:
#   1. detect OS/context
#   2. run the matching bootstrap script (installs git, ansible, chezmoi, ...)
#   3. clone the engine repo into ~/.rocket-launch
#   4. hand over to `rocket provision`
#
set -euo pipefail

RL_REPO_URL="${RL_REPO_URL:-https://github.com/oheinemann/rocket-launch.git}"
RL_HOME="${RL_HOME:-$HOME/.rocket-launch}"
RL_CONFIG_REPO_DEFAULT="https://github.com/oheinemann/rocket-launch-config.git"
RL_CONFIG_REPO=""

# ----------------------------------------------------------------------------
# Parse arguments
# ----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --config) RL_CONFIG_REPO="$2"; shift 2 ;;
    --config=*) RL_CONFIG_REPO="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: install.sh [--config <git-url>]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -z "$RL_CONFIG_REPO" ] && RL_CONFIG_REPO="$RL_CONFIG_REPO_DEFAULT"
export RL_CONFIG_REPO

# ----------------------------------------------------------------------------
# Locate engine sources: either we run from a checkout, or we bootstrap from
# the network (curl | bash) and need a temporary copy to source helpers from.
# ----------------------------------------------------------------------------
SCRIPT_DIR=""
if _rl_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"; then
  SCRIPT_DIR="$_rl_dir"
fi
if [ -f "$SCRIPT_DIR/lib/detect-os.sh" ]; then
  RL_SRC="$SCRIPT_DIR"
else
  RL_SRC="$(mktemp -d)"
  echo "==> Fetching rocket-launch engine ..."
  # A fresh machine has no git yet — the bootstrap (below) installs it. So fetch
  # the engine as a tarball via curl; fall back to git only if curl is missing.
  RL_REPO_BRANCH="${RL_REPO_BRANCH:-main}"
  RL_TARBALL="${RL_REPO_URL%.git}/archive/refs/heads/${RL_REPO_BRANCH}.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RL_TARBALL" | tar -xz -C "$RL_SRC" --strip-components=1 \
      || { echo "!!! failed to fetch engine tarball ($RL_TARBALL)" >&2; exit 1; }
  elif command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$RL_REPO_URL" "$RL_SRC" >/dev/null 2>&1 \
      || { echo "!!! git clone failed" >&2; exit 1; }
  else
    echo "!!! need curl or git to fetch the engine" >&2; exit 1
  fi
fi

# shellcheck disable=SC1091
. "$RL_SRC/lib/log.sh"
# shellcheck disable=SC1091
. "$RL_SRC/lib/detect-os.sh"

echo
log "rocket-launch — OS=$RL_OS context=$RL_CONTEXT arch=$RL_ARCH wsl=$RL_WSL"
log "config repo: $RL_CONFIG_REPO"
echo

# ----------------------------------------------------------------------------
# Phase 0 — bootstrap (per OS): get git + ansible + chezmoi available
# ----------------------------------------------------------------------------
BOOTSTRAP="$RL_SRC/bootstrap/${RL_CONTEXT}.sh"
[ -f "$BOOTSTRAP" ] || abort "No bootstrap script for context '$RL_CONTEXT' ($BOOTSTRAP)."
log "Phase 0: bootstrap ($RL_CONTEXT)"
# Source with stdin from /dev/null: we may be running via `curl | bash`, where
# the script itself is on stdin. Child installers (Homebrew, brew) that read
# stdin would otherwise consume the rest of this script and Phase 1 would never
# run. Interactive sudo inside the bootstrap reads /dev/tty explicitly.
# shellcheck disable=SC1090
. "$BOOTSTRAP" </dev/null

# ----------------------------------------------------------------------------
# Install the engine into a stable location and expose `rocket` on PATH
# ----------------------------------------------------------------------------
if [ ! -d "$RL_HOME/.git" ]; then
  logn "Cloning engine into $RL_HOME:"; git clone "$RL_REPO_URL" "$RL_HOME" >/dev/null 2>&1; logk
else
  logn "Updating engine in $RL_HOME:"; git -C "$RL_HOME" pull --ff-only >/dev/null 2>&1 || true; logk
fi
# git may not carry the executable bit across every setup (existing clones, core.fileMode),
# so guarantee it — this also makes the `rocket` symlink runnable.
chmod +x "$RL_HOME/bin/rocket.sh" 2>/dev/null || true
# Expose a clean `rocket` command via a symlink in ~/.local/bin.
mkdir -p "$HOME/.local/bin"
ln -sf "$RL_HOME/bin/rocket.sh" "$HOME/.local/bin/rocket"
export PATH="$HOME/.local/bin:$PATH"

# ----------------------------------------------------------------------------
# Phase 1 — provisioning (ansible + chezmoi, data-driven from config repo)
# ----------------------------------------------------------------------------
log "Phase 1: provision"
# Invoke via bash so a missing executable bit can never block Phase 1.
bash "$RL_HOME/bin/rocket.sh" provision --config "$RL_CONFIG_REPO"

echo
log "Done. Open a new shell to pick up PATH and shell config."
