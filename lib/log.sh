#!/usr/bin/env bash
# Shared logging helpers for rocket-launch (POSIX/bash).
# Source this file: . "$(dirname "$0")/../lib/log.sh"

# Colors (real escape bytes via ANSI-C quoting; empty when not a TTY).
# Real bytes let us pass them as printf %s arguments (avoids SC2059).
if [ -t 1 ]; then
  RL_BOLD=$'\033[1m'; RL_RED=$'\033[91m'; RL_GREEN=$'\033[92m'
  RL_BLUE=$'\033[94m'; RL_YELLOW=$'\033[93m'; RL_END=$'\033[0m'
else
  RL_BOLD=''; RL_RED=''; RL_GREEN=''; RL_BLUE=''; RL_YELLOW=''; RL_END=''
fi

log()   { printf '%s==>%s %s%s%s\n' "$RL_BLUE" "$RL_END" "$RL_BOLD" "$*" "$RL_END"; }
logn()  { printf '%s==>%s %s%s%s '  "$RL_BLUE" "$RL_END" "$RL_BOLD" "$*" "$RL_END"; }
logk()  { printf '%sOK%s\n'         "$RL_GREEN" "$RL_END"; }
warn()  { printf '%s!!! %s%s\n'     "$RL_YELLOW" "$*" "$RL_END" >&2; }
error() { printf '%s%s!!! %s%s\n'   "$RL_BOLD" "$RL_RED" "$*" "$RL_END" >&2; }
abort() { error "$*"; exit 1; }

# Append a block to a file once, guarded by a unique marker line (idempotent).
# Creates the file if missing. Used by bootstraps to persist PATH additions to
# login shell profiles so new terminals see brew/gh/chezmoi/rocket immediately.
rl_append_once() {
  local file="$1" marker="$2" block="$3"
  grep -qF "$marker" "$file" 2>/dev/null && return 0
  printf '\n%s\n%s\n' "$marker" "$block" >> "$file" 2>/dev/null || true
}
