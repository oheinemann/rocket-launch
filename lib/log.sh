#!/usr/bin/env bash
# Shared logging helpers for rocket-launch (POSIX/bash).
# Source this file: . "$(dirname "$0")/../lib/log.sh"

# Colors (disabled when not a TTY)
if [ -t 1 ]; then
  RL_BOLD='\033[1m'; RL_RED='\033[91m'; RL_GREEN='\033[92m'
  RL_BLUE='\033[94m'; RL_YELLOW='\033[93m'; RL_END='\033[0m'
else
  RL_BOLD=''; RL_RED=''; RL_GREEN=''; RL_BLUE=''; RL_YELLOW=''; RL_END=''
fi

log()   { printf "${RL_BLUE}==>${RL_END} ${RL_BOLD}%s${RL_END}\n" "$*"; }
logn()  { printf "${RL_BLUE}==>${RL_END} ${RL_BOLD}%s${RL_END} " "$*"; }
logk()  { printf "${RL_GREEN}OK${RL_END}\n"; }
warn()  { printf "${RL_YELLOW}!!! %s${RL_END}\n" "$*" >&2; }
error() { printf "${RL_BOLD}${RL_RED}!!! %s${RL_END}\n" "$*" >&2; }
abort() { error "$*"; exit 1; }
