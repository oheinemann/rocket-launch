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
