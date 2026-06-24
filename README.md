# 🚀 rocket-launch

Bring a fresh machine to a defined, ready-to-work state in minutes — on
**macOS**, **Windows 10/11 + WSL2**, and **Fedora**.

rocket-launch is the **engine** (this repo, public). Your personal apps and
settings live in a separate **private config repo** that you point the installer
at — or it falls back to a public example config.

> v2 rewrite. The original Windows/WSL-only version is preserved in the
> `v1-legacy` branch.

## How it works

Two phases, like before — but OS-agnostic and data-driven:

1. **Bootstrap (Phase 0)** — a tiny per-OS script installs git, Ansible and
   chezmoi.
2. **Provision (Phase 1)** — Ansible installs your apps and chezmoi applies your
   dotfiles, both driven entirely by your config repo.

```
engine (public)                  config (private)
├── install.sh / install.ps1     ├── machines.yml      hostname → profiles
├── bin/rocket.sh                ├── profiles/*.yml    bundles of logical apps
├── bootstrap/<os>.sh|ps1        ├── windows-host.txt  winget ids (host GUI apps)
├── ansible/ (roles, site.yml)   └── dotfiles/         chezmoi source (+ op:// refs)
└── lib/package-map.yml          (logical app → per-OS manager/id)
```

## Quickstart

### macOS / Fedora / Linux & WSL
```bash
curl -fsSL https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.sh \
  | bash -s -- --config git@github.com:you/rocket-launch-config.git
```
Omit `--config` to use the public example config.

### Windows 10 / 11 (one command, one reboot)
Run in an **elevated** PowerShell:
```powershell
iex "& { $(irm https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.ps1) } -Config https://github.com/you/rocket-launch-config.git"
```
If WSL2 isn't set up yet, it installs it, **auto-resumes after the reboot**
(no second manual run), provisions Windows host apps via **winget**, then runs
the Linux installer inside WSL.

## Per-machine setup

Machines are matched by **hostname** to reusable **profiles** in `machines.yml`:

```yaml
machines:
  olli-thinkpad: { os: windows, profiles: [base, dev, workstation] }
  olli-macbook:  { os: macos,   profiles: [base, dev, laptop] }
  olli-mobile:   { os: macos,   profiles: [base, laptop] }   # lean
defaults:
  profiles: [base]
```

Mobile/portable machines get lean profiles; fixed workstations get the full set.

## Package abstraction

Profiles list **logical** app names; the engine resolves them per OS via
`lib/package-map.yml`:

```yaml
slack:
  macos: { mgr: brew-cask, id: slack }
  dnf:   { mgr: flatpak,   id: com.slack.Slack }
  # WSL: Slack runs on the Windows host (windows-host.txt)
```

## CLI

```bash
rocket doctor      # show detected env + tool availability
rocket bootstrap   # (re)run Phase 0 for this OS
rocket provision --config <git-url>   # (re)run Phase 1
```

## Supported targets

macOS · Windows 10/WSL2 · Windows 11/WSL2 · Fedora 44

## Secrets

No secrets in any repo. chezmoi resolves `op://` references through the
1Password CLI at apply time (SSH keys, WireGuard config, …).

## Status

v2 is an early **alpha** scaffold (Phase A). See the design notes for the
roadmap (package roles, shell/chezmoi/1Password/WireGuard, CI across all OSes).
