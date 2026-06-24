#!/usr/bin/env bash
# OS / architecture / context detection for rocket-launch.
# Sourcing this file exports:
#   RL_OS       macos | linux | windows
#   RL_DISTRO   fedora | ubuntu | debian | ""        (linux only)
#   RL_ARCH     arm64 | x86_64
#   RL_WSL      true | false
#   RL_CONTEXT  macos | fedora | wsl | linux | windows-host
#
# RL_CONTEXT is the value used to select the matching bootstrap script.

detect_os() {
  RL_WSL=false
  RL_DISTRO=""

  case "$(uname -s 2>/dev/null)" in
    Darwin)
      RL_OS="macos"
      RL_CONTEXT="macos"
      ;;
    Linux)
      RL_OS="linux"
      RL_CONTEXT="linux"
      # WSL detection: WSL2 reports "microsoft" in the kernel string.
      if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        RL_WSL=true
        RL_CONTEXT="wsl"
      fi
      # Distro from os-release (id is lowercase: fedora, ubuntu, debian, ...)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        RL_DISTRO="$(. /etc/os-release && printf '%s' "$ID")"
      fi
      # On bare-metal Linux we currently target Fedora explicitly.
      if [ "$RL_WSL" = false ] && [ "$RL_DISTRO" = "fedora" ]; then
        RL_CONTEXT="fedora"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      RL_OS="windows"
      RL_CONTEXT="windows-host"
      ;;
    *)
      RL_OS="unknown"
      RL_CONTEXT="unknown"
      ;;
  esac

  case "$(uname -m 2>/dev/null)" in
    arm64|aarch64) RL_ARCH="arm64" ;;
    x86_64|amd64)  RL_ARCH="x86_64" ;;
    *)             RL_ARCH="$(uname -m 2>/dev/null)" ;;
  esac

  export RL_OS RL_DISTRO RL_ARCH RL_WSL RL_CONTEXT
}

detect_os
