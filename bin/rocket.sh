#!/usr/bin/env bash
#
# rocket — command dispatcher for rocket-launch.
#
# Usage:
#   rocket <command> [options]
#
# Commands:
#   bootstrap            Run Phase 0 (install git/ansible/chezmoi for this OS)
#   provision            Run Phase 1 (ansible playbook + chezmoi apply)
#   doctor               Print detected environment and tool availability
#   version              Print the engine version
#   help                 Show this help
#
set -euo pipefail

RL_HOME="${RL_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$RL_HOME/lib/log.sh"
# shellcheck disable=SC1091
. "$RL_HOME/lib/detect-os.sh"

RL_CONFIG_HOME="${RL_CONFIG_HOME:-$HOME/.rocket-launch-config}"
RL_CONFIG_REPO_DEFAULT="https://github.com/oheinemann/rocket-launch-config.git"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

cmd_doctor() {
  log "Environment"
  printf "  OS       : %s\n" "$RL_OS"
  printf "  Context  : %s\n" "$RL_CONTEXT"
  printf "  Distro   : %s\n" "${RL_DISTRO:-n/a}"
  printf "  Arch     : %s\n" "$RL_ARCH"
  printf "  WSL      : %s\n" "$RL_WSL"
  printf "  Hostname : %s\n" "$(hostname)"
  echo
  log "Tools"
  for t in git ansible ansible-playbook chezmoi op; do
    if command -v "$t" >/dev/null 2>&1; then
      printf "  %-16s %s\n" "$t" "$(command -v "$t")"
    else
      printf "  %-16s ${RL_RED}missing${RL_END}\n" "$t"
    fi
  done
}

cmd_bootstrap() {
  local script="$RL_HOME/bootstrap/${RL_CONTEXT}.sh"
  [ -f "$script" ] || abort "No bootstrap script for context '$RL_CONTEXT'."
  # shellcheck disable=SC1090
  . "$script"
}

clone_or_update_config() {
  local repo="$1"
  if [ ! -d "$RL_CONFIG_HOME/.git" ]; then
    logn "Cloning config repo:"; git clone "$repo" "$RL_CONFIG_HOME" >/dev/null 2>&1; logk
  else
    logn "Updating config repo:"; git -C "$RL_CONFIG_HOME" pull --ff-only >/dev/null 2>&1 || true; logk
  fi
}

cmd_provision() {
  local config_repo="$RL_CONFIG_REPO_DEFAULT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --config) config_repo="$2"; shift 2 ;;
      --config=*) config_repo="${1#*=}"; shift ;;
      *) shift ;;
    esac
  done

  clone_or_update_config "$config_repo"

  command -v ansible-playbook >/dev/null 2>&1 || abort "ansible-playbook missing — run 'rocket bootstrap' first."

  log "Running ansible playbook"
  ansible-playbook \
    -i "$RL_HOME/ansible/inventory/local.yml" \
    -e "rl_config_home=$RL_CONFIG_HOME" \
    -e "rl_context=$RL_CONTEXT" \
    -e "rl_hostname=$(hostname)" \
    "$RL_HOME/ansible/site.yml" "$@"
}

main() {
  local command="${1:-help}"; shift || true
  case "$command" in
    bootstrap) cmd_bootstrap "$@" ;;
    provision) cmd_provision "$@" ;;
    doctor)    cmd_doctor "$@" ;;
    version)   cat "$RL_HOME/VERSION" 2>/dev/null || echo "dev" ;;
    help|-h|--help) usage ;;
    *) error "Unknown command: $command"; echo; usage; exit 1 ;;
  esac
}

main "$@"
