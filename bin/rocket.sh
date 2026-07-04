#!/usr/bin/env bash
#
# rocket — command dispatcher for rocket-launch.
#
# Usage:
#   rocket <command> [options]
#
# Commands:
#   bootstrap            Run Phase 0 (install git/ansible/chezmoi for this OS)
#   provision [--no-sudo]  Run Phase 1 (ansible playbook + chezmoi apply)
#   doctor               Print detected environment and tool availability
#   version              Print the engine version
#   help                 Show this help
#
set -euo pipefail

# Resolve this script's real path even when invoked via the ~/.local/bin/rocket
# symlink, so RL_HOME points at the engine checkout (not ~/.local).
_rl_src="${BASH_SOURCE[0]}"
while [ -h "$_rl_src" ]; do
  _rl_dir="$(cd -P "$(dirname "$_rl_src")" >/dev/null 2>&1 && pwd)"
  _rl_src="$(readlink "$_rl_src")"
  case "$_rl_src" in /*) ;; *) _rl_src="$_rl_dir/$_rl_src" ;; esac
done
RL_HOME="${RL_HOME:-$(cd -P "$(dirname "$_rl_src")/.." >/dev/null 2>&1 && pwd)}"
# shellcheck disable=SC1091
. "$RL_HOME/lib/log.sh"
# shellcheck disable=SC1091
. "$RL_HOME/lib/detect-os.sh"

# Resolve the machine name to match against machines.yml keys. On macOS the
# `hostname` command is network-derived (can be a FQDN like name.fritz.box or a
# fallback like "Mac"), so prefer the stable LocalHostName / ComputerName.
resolve_hostname() {
  local h=""
  if [ "${RL_CONTEXT:-}" = macos ] || [ "${RL_OS:-}" = macos ]; then
    h="$(scutil --get LocalHostName 2>/dev/null || true)"
    [ -n "$h" ] || h="$(scutil --get ComputerName 2>/dev/null || true)"
  fi
  [ -n "$h" ] || h="$(hostname 2>/dev/null || true)"
  printf '%s' "${h%%.*}"
}

RL_CONFIG_HOME="${RL_CONFIG_HOME:-$HOME/.rocket-launch-config}"
RL_CONFIG_REPO_DEFAULT="https://github.com/oheinemann/rocket-launch-config.git"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

# -----------------------------------------------------------------------------
# GitHub auth helpers for first-run bootstrap (RL-23)
# -----------------------------------------------------------------------------

# Convert SSH URL to HTTPS URL if needed.
# git@github.com:org/repo.git -> https://github.com/org/repo.git
# git@github.com:org/repo     -> https://github.com/org/repo.git
# HTTPS URLs pass through unchanged.
ssh_to_https_url() {
  local url="$1"
  if [[ "$url" =~ ^git@github\.com:(.+)$ ]]; then
    local path="${BASH_REMATCH[1]}"
    # Strip trailing .git if present, then re-add it for consistency
    path="${path%.git}"
    printf 'https://github.com/%s.git' "$path"
  else
    # Already HTTPS or other format — return as-is
    printf '%s' "$url"
  fi
}

# Install gh CLI if not present. Returns 0 on success, 1 on failure.
ensure_gh() {
  command -v gh >/dev/null 2>&1 && return 0

  log "Installing GitHub CLI (gh)..."

  case "$RL_CONTEXT" in
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found — cannot install gh."
        return 1
      fi
      brew install gh >/dev/null 2>&1 || { warn "Failed to install gh via brew."; return 1; }
      ;;
    fedora)
      sudo dnf install -y gh >/dev/null 2>&1 || { warn "Failed to install gh via dnf."; return 1; }
      ;;
    wsl|linux)
      # gh apt repository (deb822 style)
      local arch
      arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
      local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
      local source_file="/etc/apt/sources.list.d/github-cli.sources"

      # Create keyrings directory if needed
      sudo mkdir -p /etc/apt/keyrings

      # Download GPG key
      if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
           | sudo tee "$keyring" >/dev/null 2>&1; then
        warn "Failed to download gh GPG key."
        return 1
      fi
      sudo chmod 644 "$keyring"

      # Write deb822-style source file
      printf 'Types: deb\nURIs: https://cli.github.com/packages\nSuites: stable\nComponents: main\nArchitectures: %s\nSigned-By: %s\n' \
        "$arch" "$keyring" | sudo tee "$source_file" >/dev/null

      # Update and install
      if ! sudo apt-get update >/dev/null 2>&1; then
        warn "apt-get update failed."
        return 1
      fi
      if ! sudo apt-get install -y gh >/dev/null 2>&1; then
        warn "Failed to install gh via apt."
        return 1
      fi
      ;;
    *)
      warn "Cannot install gh on context '$RL_CONTEXT'."
      return 1
      ;;
  esac

  command -v gh >/dev/null 2>&1
}

# Attempt to establish GitHub access for the config repo.
# Tries token-based auth first, then interactive gh auth.
# Sets CLONED_VIA_TOKEN=true if the repo was cloned with a token.
# Returns 0 if auth was established (or clone succeeded), 1 otherwise.
ensure_github_access() {
  local repo="$1"
  CLONED_VIA_TOKEN=false

  # --- A) Non-interactive token path (CI/headless) ---
  local token="${RL_CONFIG_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
  if [ -n "$token" ]; then
    log "Using token from environment for config repo..."

    # Convert SSH URL to HTTPS for token auth
    local https_url
    https_url="$(ssh_to_https_url "$repo")"

    # Extract org/repo path from HTTPS URL
    local repo_path
    if [[ "$https_url" =~ ^https://github\.com/(.+)$ ]]; then
      repo_path="${BASH_REMATCH[1]}"
      repo_path="${repo_path%.git}"
    else
      warn "Cannot parse repository URL: $https_url"
      return 1
    fi

    # Clone with token (output suppressed to avoid leaking token in error messages)
    if git clone "https://x-access-token:${token}@github.com/${repo_path}.git" "$RL_CONFIG_HOME" >/dev/null 2>&1; then
      # Immediately remove token from stored remote URL
      git -C "$RL_CONFIG_HOME" remote set-url origin "https://github.com/${repo_path}.git" >/dev/null 2>&1
      CLONED_VIA_TOKEN=true
      return 0
    else
      warn "Token-based clone failed."
      return 1
    fi
  fi

  # --- B) No token: install gh so the tool is ready, then fall through to the
  #        caller's manual guidance. gh's interactive login TUI (arrow-key menus)
  #        cannot run reliably inside `curl | bash` — the outer shell already holds
  #        the terminal, so gh aborts with "unexpected escape sequence from
  #        terminal". The user runs `gh auth login` in their own terminal instead.
  ensure_gh || true
  return 1
}

cmd_doctor() {
  log "Environment"
  printf "  OS       : %s\n" "$RL_OS"
  printf "  Context  : %s\n" "$RL_CONTEXT"
  printf "  Distro   : %s\n" "${RL_DISTRO:-n/a}"
  printf "  Arch     : %s\n" "$RL_ARCH"
  printf "  WSL      : %s\n" "$RL_WSL"
  printf "  Hostname : %s\n" "$(resolve_hostname)"
  echo
  log "Tools"
  for t in git ansible ansible-playbook chezmoi op; do
    if command -v "$t" >/dev/null 2>&1; then
      printf "  %-16s %s\n" "$t" "$(command -v "$t")"
    else
      printf '  %-16s %smissing%s\n' "$t" "$RL_RED" "$RL_END"
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
    logn "Cloning config repo:"
    if git clone "$repo" "$RL_CONFIG_HOME" >/dev/null 2>&1; then
      logk
    else
      echo
      # First clone attempt failed — try to establish auth and retry once.
      if ensure_github_access "$repo"; then
        # Auth established (or repo cloned via token)
        if [ "$CLONED_VIA_TOKEN" = true ]; then
          # Already cloned during token auth
          log "Config repo cloned successfully."
        else
          # Auth configured via gh — retry clone
          logn "Retrying clone:"
          if git clone "$repo" "$RL_CONFIG_HOME" >/dev/null 2>&1; then
            logk
          else
            echo
            warn "Clone still failed after authentication."
            warn "Could not clone the private config repo:"
            warn "  $repo"
            abort "Re-run after verifying GitHub access: rocket provision --config $repo"
          fi
        fi
      else
        # Could not obtain access — clear, copy-pasteable next steps.
        local https_repo
        https_repo="$(ssh_to_https_url "$repo")"
        warn "Cannot access the private config repo yet:"
        warn "  $repo"
        warn "Authenticate GitHub in a SEPARATE terminal, then re-run. Easiest:"
        warn "  1) gh auth login       # GitHub.com → HTTPS → Login with a web browser"
        warn "  2) rocket provision --config $https_repo"
        warn "(gh is installed. Alternatively: 1Password SSH agent for the SSH URL,"
        warn " or set RL_CONFIG_TOKEN=<PAT> for non-interactive auth.)"
        abort "Re-run after authenticating."
      fi
    fi
  else
    logn "Updating config repo:"; git -C "$RL_CONFIG_HOME" pull --ff-only >/dev/null 2>&1 || true; logk
  fi
}

cmd_provision() {
  local config_repo="$RL_CONFIG_REPO_DEFAULT"
  local no_sudo=false
  local passthrough=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --config) config_repo="$2"; shift 2 ;;
      --config=*) config_repo="${1#*=}"; shift ;;
      --no-sudo) no_sudo=true; shift ;;
      *) passthrough+=("$1"); shift ;;   # forwarded to ansible-playbook
    esac
  done

  clone_or_update_config "$config_repo"

  command -v ansible-playbook >/dev/null 2>&1 || abort "ansible-playbook missing — run 'rocket bootstrap' first."

  # Prompt for the sudo password only when it's actually needed: if passwordless
  # sudo already works, skip it; otherwise let ansible ask once. --no-sudo opts out.
  local become_args=()
  if [ "$no_sudo" != true ]; then
    # Prime sudo once and keep the timestamp fresh for the whole run. This covers
    # BOTH ansible become tasks AND Homebrew's internal `sudo installer` for
    # pkg-based casks (e.g. microsoft-teams), which otherwise fail mid-run with
    # "sudo: a terminal is required to read the password".
    if ! sudo -n true 2>/dev/null; then
      log "Administrator rights are needed (some apps install via a pkg installer)."
      sudo -v || abort "Could not obtain sudo access (needed for pkg-based apps)."
    fi
    ( while true; do sudo -n true 2>/dev/null || break; sleep 50; done ) &
    _rl_sudo_pid=$!
    trap 'kill "${_rl_sudo_pid:-}" 2>/dev/null || true' EXIT
  fi

  local rl_hostname
  rl_hostname="$(resolve_hostname)"
  log "Resolving host as: $rl_hostname"

  log "Running ansible playbook"
  ansible-playbook \
    -i "$RL_HOME/ansible/inventory/local.yml" \
    -e "rl_config_home=$RL_CONFIG_HOME" \
    -e "rl_context=$RL_CONTEXT" \
    -e "rl_hostname=$rl_hostname" \
    ${become_args[@]+"${become_args[@]}"} \
    "$RL_HOME/ansible/site.yml" \
    ${passthrough[@]+"${passthrough[@]}"}
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
