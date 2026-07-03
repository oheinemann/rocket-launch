# rocket-launch-config (example)

This is a **template** for your private config repo. Copy it into a new repo
(e.g. `rocket-launch-config`), keep it private, and point the installer at it:

```bash
curl -fsSL https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.sh \
  | bash -s -- --config git@github.com:you/rocket-launch-config.git
```

## Layout

| Path | Purpose |
|------|---------|
| `machines.yml` | Hostname → profiles mapping (+ `defaults` fallback). |
| `profiles/*.yml` | Reusable bundles of logical package names (e.g. `base`, `dev`, `personal`). |
| `windows-host.txt` | winget ids for Windows host GUI apps. |
| `dotfiles/` | chezmoi source for your dotfiles (+ `op://` secret refs). |

## How resolution works

1. The engine looks up your **hostname** in `machines.yml` → list of profiles.
2. It unions the `packages:` from each profile.
3. Each logical name is resolved to the right manager via the engine's
   `lib/package-map.yml` (brew/cask, apt, dnf, flatpak; winget on the Windows host).

Add a new machine = one entry in `machines.yml`. Add a new app = add it to a
profile and ensure it exists in the engine `package-map.yml`.

## Personal Profile

The `personal` profile bundles GUI apps you want on every machine with a display:

| App | macOS | Fedora | WSL | Windows-Host |
|-----|-------|--------|-----|--------------|
| **Claude Desktop** | cask `claude` | skipped | skipped | winget `Anthropic.Claude` |
| **Obsidian** | cask `obsidian` | flatpak `md.obsidian.Obsidian` | skipped | winget `Obsidian.Obsidian` |

**Note:** Claude Desktop has no official Linux package. It is silently skipped on
Linux/WSL (no "unresolved" warning). On WSL machines, both apps run on the
Windows host via winget.

## macOS Defaults

On macOS hosts, the `macos-defaults` role applies system settings from the
`macos_defaults` key in profiles. These are applied idempotently using
`osx_defaults` (no raw `defaults write`).

### Capture Workflow

To capture new settings from a fresh Mac:

1. **Snapshot before:** `defaults read > ~/before.txt`
2. **Configure manually:** Use System Settings, Finder preferences, etc.
3. **Snapshot after:** `defaults read > ~/after.txt`
4. **Diff:** `diff ~/before.txt ~/after.txt` shows exactly which domains/keys changed.
5. **Add to profile:** Copy relevant entries to `profiles/macos.yml` as
   `macos_defaults` entries with `{domain, key, type, value}`.

### App Preferences — Where to Put What

| Preference Class | Examples | Managed By |
|-----------------|----------|------------|
| `defaults` domain | iTerm2, Terminal, Rectangle, Raycast (partly) | `macos_defaults` in profile |
| File in `~` or `~/.config` | VS Code `settings.json`, `.editorconfig` | chezmoi (`chezmoi add`) |
| App-Store sync / GUI login | Raycast Cloud, app-specific sync accounts | Manual (see checklist below) |

### Manual Checklist (Not Automatable)

These require manual setup after provisioning:

- [ ] **App Permissions / TCC:** Camera, Microphone, Full Disk Access, Accessibility
      (System Settings > Privacy & Security)
- [ ] **Login Items:** Apps that start at login (System Settings > General > Login Items)
- [ ] **App Store / iCloud:** Sign in to App Store, iCloud (for app sync)
- [ ] **App-specific cloud sync:** Raycast sync, 1Password account, etc.

## 1Password: GUI vs. CLI — Where What Lives

**Rule of thumb:** GUI follows the screen, CLI follows the shell.

| Context | CLI (`op`) | Desktop GUI | Notes |
|---------|:----------:|:-----------:|-------|
| macOS | yes | yes | Both via engine (`onepassword` role) |
| Fedora | yes | yes | Both via engine (`onepassword` role) |
| Linux-Desktop | yes | yes | Both via engine (`onepassword` role) |
| **WSL2** | yes | **no** | CLI via apt; GUI runs on **Windows host** |
| **Windows-Host** | (via App) | yes | `AgileBits.1Password` in `windows-host.txt` |

### WSL2 Integration Checklist (Manual)

The 1Password CLI inside WSL2 uses the Windows desktop app for authentication.
After provisioning, enable this bridge in the **Windows 1Password app**
(exact UI paths may vary by version — consult current 1Password documentation):

- [ ] **Settings > Developer > Integrate with 1Password CLI** — enable
- [ ] **Settings > Developer > SSH Agent** — enable (for `op://` SSH key access)
- [ ] If prompted, allow the WSL integration toggle

Once enabled:
- `op signin` in WSL uses Windows biometrics
- `ssh -T git@github.com` works via the 1Password SSH agent
- chezmoi `op://` references resolve seamlessly

## WireGuard VPN (Laptop Profile)

WireGuard is installed on devices with the `laptop` profile — mobile devices that
need VPN access to the home network. Fixed desktops (`workstation` profile) do not
get WireGuard.

### Config via 1Password

Each laptop has its own WireGuard tunnel config (unique keys — create one per
device in the FritzBox). Store each config as a **field** (or secure note) in
1Password, in an item **named after the hostname**. The reference is then
**derived automatically** — no `machines.yml` entry needed:

```
op://Private/<hostname>/config      # e.g. op://Private/olli-macbook/config
```

Add an explicit `wireguard_op_ref` in `machines.yml` **only to override** (a
different vault or item name):

```yaml
olli-mobile:
  os: macos
  profiles: [base, laptop, macos]
  wireguard_op_ref: "op://Work/WireGuard-Mobile/config"   # override
```

At provision time, the `wireguard` role:
1. Installs `wireguard-tools` via the system package manager
2. Reads the config from 1Password (`op read` on the derived/overridden ref)
3. Writes it to `~/.config/wireguard/wg0.conf` (mode 0600)

> Tip: in the FritzBox, choose **split tunnel** (only the home network in
> `AllowedIPs`) if you want the tunnel to reach the home LAN without routing all
> your traffic through it.

**Prerequisite:** 1Password CLI must be authenticated (`op signin`). On macOS with
the 1Password desktop app, the CLI integration provides automatic authentication.

### Manual Connection

No autostart is configured. Connect when needed (outside home network):

```bash
# Connect
sudo wg-quick up ~/.config/wireguard/wg0.conf

# Disconnect
sudo wg-quick down ~/.config/wireguard/wg0.conf

# Status
sudo wg show
```

### WSL / Windows Laptops

For Windows laptops running WSL, WireGuard is **not** installed inside WSL. Instead,
use the WireGuard GUI on the Windows host (install via winget: `WireGuard.WireGuard`
in `windows-host.txt`). The Windows tunnel covers all traffic including WSL.

## Docker "Wohin" Doctrine

| Context | Docker Source | Notes |
|---------|---------------|-------|
| **macOS** | OrbStack (brew-cask) | Installed via package-map |
| **WSL2** | native docker-ce (apt) | `docker-ce` role, requires systemd |
| **Fedora** | docker-ce (dnf) | `docker-ce` role |
| **Linux-Desktop** | docker-ce (apt) | `docker-ce` role |
| **Windows-Host** | — | Not needed; Docker runs in WSL |

The `docker-ce` role installs Docker from the official `download.docker.com`
repository (not the conflicting `docker.io` / `moby` packages from distro repos).

### Post-Provision: docker Group

After provisioning, the current user is added to the `docker` group. This change
requires a **new login session** to take effect:

```bash
# Option 1: Log out and back in
# Option 2: Start a new group session (current shell only)
newgrp docker
# Verify:
docker run hello-world
```

### WSL2 systemd Checklist (Manual)

WSL2 requires systemd to run the Docker service. The `docker-ce` role enables
this in `/etc/wsl.conf`, but a manual restart is required:

- [ ] **Verify wsl.conf:** Check that `/etc/wsl.conf` contains:
      ```ini
      [boot]
      systemd=true
      ```
- [ ] **Restart WSL (from Windows PowerShell):**
      ```powershell
      wsl --shutdown
      ```
- [ ] **Reopen WSL terminal** — systemd should now be running
- [ ] **Verify Docker:** `docker run hello-world` (without sudo)

If Docker still fails after restart, check `systemctl status docker`.

## DDEV (Local Development Environment)

DDEV is installed via the dedicated `ddev` role (not through `package-map.yml`),
automatically triggered when the `dev` profile is active. The role:

1. Verifies Docker is available (prerequisite check)
2. Installs DDEV via Homebrew tap (macOS) or apt/dnf repo (Linux/WSL/Fedora)
3. Installs mkcert for trusted local HTTPS certificates
4. Runs `mkcert -install` to register the local CA in the system trust store

### Control Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ddev_install` | `true` | Install DDEV |
| `ddev_install_mkcert` | `true` | Install mkcert |
| `ddev_run_mkcert_install` | `true` | Run `mkcert -install` to set up local CA |

### WSL2 Browser Trust (Manual)

For browsers on the **Windows host** to trust DDEV's local HTTPS certificates,
the mkcert CA must be shared between WSL and Windows. The exact steps may vary
by DDEV/mkcert version — consult the current DDEV documentation:

- [ ] **Option A (recommended):** Set `CAROOT` in WSL to a Windows-accessible path
      (e.g., `/mnt/c/Users/YourName/.mkcert`) and run `mkcert -install` on both sides
- [ ] **Option B:** Copy the CA files from WSL's `$(mkcert -CAROOT)` to Windows
      and import `rootCA.pem` into the Windows certificate store

Once configured, DDEV sites will show trusted HTTPS in Chrome/Edge/Firefox on Windows.

## Syncthing (Personal Profile)

Syncthing is installed on devices with the `personal` profile and syncs the
`~/Sync` folder with the Synology NAS.

### Installation per OS

| Context | Install | Service |
|---------|---------|---------|
| macOS | `brew install syncthing` | `brew services` (launchd, user) |
| Fedora | `dnf install syncthing` | `systemd --user` + `loginctl enable-linger` |
| Debian/Ubuntu | apt (syncthing.net repo) | `systemd --user` + `loginctl enable-linger` |
| **WSL** | skipped | runs on Windows host |
| Windows-Host | winget `Syncthing.Syncthing` | Tray app |

### REST API Configuration

After the service starts, the role configures Syncthing via its REST API:

1. Adds the Synology as a remote device (Device ID from 1Password)
2. Creates the `~/Sync` folder shared with the Synology

The Synology Device ID is read from 1Password at runtime:

```
syncthing_synology_op_ref: "op://Private/Syncthing-Synology/device-id"
```

Override per host in `machines.yml` if needed.

### loginctl enable-linger (Linux)

On Linux, the role enables `loginctl enable-linger` for the current user. This
ensures the Syncthing user service starts at boot, even without an active login
session.

### Manual Step: Synology Accept

Syncthing pairing is **two-sided**: each new device must be accepted by the
Synology. The engine can only configure the local side. On the Synology:

- **Option A (recommended):** Enable "Auto Accept" for the sync folder in the
  Synology Syncthing settings. New devices are accepted automatically.
- **Option B:** Manually confirm each new device in the Synology Syncthing web UI
  when it appears as "pending".

After acceptance, the folder will start syncing.

### WSL / Windows

For WSL machines, Syncthing is **not** installed inside WSL. Instead, Syncthing
runs on the Windows host (via winget: `Syncthing.Syncthing` in `windows-host.txt`).

If WSL needs access to the synced folder, create a symlink via chezmoi:

```bash
# Example: link ~/Sync to the Windows sync folder
ln -s /mnt/c/Users/<username>/Sync ~/Sync
```

The exact path depends on your Windows Syncthing configuration.

## Dotfiles (chezmoi)

`dotfiles/` is a chezmoi source dir. File names use chezmoi conventions:

| Source name | Target | Notes |
|-------------|--------|-------|
| `dot_zshrc.tmpl` | `~/.zshrc` | templated (OS-aware) |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | name/email from `.chezmoidata.yaml` |
| `dot_p10k.zsh` | `~/.p10k.zsh` | prompt config |
| `.chezmoidata.yaml` | — | non-secret template data |

Templates can pull secrets at apply time, e.g.
`{{ onepasswordRead "op://Private/Item/field" }}`.

> No real secrets belong in this repo — only `op://` references that chezmoi
> resolves through the 1Password CLI at apply time.
