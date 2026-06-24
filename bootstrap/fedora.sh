#!/usr/bin/env bash
# Phase 0 bootstrap — Fedora (bare metal).
# Goal: get git, ansible and chezmoi available via dnf.
# Sourced by install.sh / `rocket bootstrap`.
set -euo pipefail

logn "Installing base packages (git, python3, ansible, chezmoi):"
# chezmoi is available in Fedora's repos.
sudo dnf install -y -q git python3 python3-pip ansible chezmoi curl >/dev/null
logk

# flatpak is the secondary GUI app source on Fedora; ensure flathub is present.
if command -v flatpak >/dev/null 2>&1; then
  logn "Ensuring Flathub remote:"
  sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  logk
fi
