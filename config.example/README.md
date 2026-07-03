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
| `windows-fonts.txt` | Nerd Font names for Windows host (optional, has defaults). |
| `windows-defaults.txt` | Registry settings for Windows host (optional, has defaults). |
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
| **Spark Mail** | cask `readdle-spark` | skipped | skipped | winget `Readdle.Spark` |
| **Firefox** | cask `firefox` | flatpak `org.mozilla.firefox` | skipped | winget `Mozilla.Firefox` |
| **Chrome** | cask `google-chrome` | flatpak `com.google.Chrome` | skipped | winget `Google.Chrome` |
| **Brave** | cask `brave-browser` | flatpak `com.brave.Browser` | skipped | winget `Brave.Brave` |
| **Postman** | cask `postman` | flatpak `com.getpostman.Postman` | skipped | winget `Postman.Postman` |

**Note:** Claude Desktop and Spark Mail have no official Linux packages. They are
silently skipped on Linux/WSL (no "unresolved" warning). On WSL machines, GUI apps
run on the Windows host via winget.

### Spark Mail — Default Mail Client

On **macOS**, the `default-mail` role automatically sets Spark as the default mail
client using `duti`. This happens when `spark` is in your profile's packages and
the system is macOS. The role sets Spark as the handler for:

- `mailto:` links
- `.eml` files

**Note:** Spark must be launched at least once before duti can register it. If
Spark has never been opened, the duti commands will fail gracefully and you can
re-run provisioning after opening Spark once.

On **Windows**, the default mail client cannot be set programmatically due to
Microsoft's `UserChoice` registry hash protection. After installing Spark,
manually set it as the default:

**Windows Default Mail Client Checklist:**

- [ ] Open **Settings** (Win+I)
- [ ] Navigate to **Apps > Default apps**
- [ ] Search for "Spark" or scroll to find it
- [ ] Click on Spark
- [ ] Set Spark as default for **MAILTO** (mail links)
- [ ] Optionally set Spark as default for **.eml** files

## Nerd Fonts (Cross-Platform)

The `fonts` role (macOS/Linux) and `windows-host.ps1` (Windows) install Nerd Fonts
for terminals, editors, and the p10k prompt.

### Default Font Set

| Font | Use Case |
|------|----------|
| **JetBrainsMono Nerd Font** | Primary editor/terminal font (recommended) |
| **FiraCode Nerd Font** | Alternative with ligatures |
| **Meslo Nerd Font** | p10k recommended font |

### Configuration After Install

After fonts are installed, configure your applications:

**Windows Terminal** (`settings.json` or GUI):
```json
{
  "profiles": {
    "defaults": {
      "fontFace": "JetBrainsMono Nerd Font"
    }
  }
}
```

**VSCode** (`settings.json`):
```json
{
  "editor.fontFamily": "'JetBrainsMono Nerd Font', Consolas, 'Courier New', monospace",
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"
}
```

**iTerm2** (macOS): Profiles > Text > Font > `JetBrainsMono Nerd Font`

### Customizing the Font List

**Linux/macOS:** Override `fonts_list` in your profile or machine config.

**Windows Host:** Create `windows-fonts.txt` in your config repo with one font
name per line. Names must match the GitHub release zip names from
[ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases).

Example `windows-fonts.txt`:
```
JetBrainsMono
FiraCode
Meslo
```

## macOS Profile

The `macos` profile includes macOS-specific system defaults (via `macos_defaults`)
and macOS-only packages:

| App | macOS | Fedora/WSL/Windows |
|-----|-------|--------------------|
| **iTerm2** | cask `iterm2` | not applicable |

iTerm2 is a macOS-only terminal emulator. On Linux/WSL, the native terminal or
installed terminal emulators are sufficient.

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
op://Private/<hostname>/config      # e.g. op://Private/example-macbook/config
```

Add an explicit `wireguard_op_ref` in `machines.yml` **only to override** (a
different vault or item name):

```yaml
example-laptop:
  os: macos
  profiles: [base, laptop, macos]
  wireguard_op_ref: "op://Work/WireGuard-Laptop/config"   # override
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

| Context | Install | Service | Config |
|---------|---------|---------|--------|
| macOS | `brew install syncthing` | `brew services` (launchd, user) | Ansible role (REST API) |
| Fedora | `dnf install syncthing` | `systemd --user` + `loginctl enable-linger` | Ansible role (REST API) |
| Debian/Ubuntu | apt (syncthing.net repo) | `systemd --user` + `loginctl enable-linger` | Ansible role (REST API) |
| **WSL** | skipped | runs on Windows host | — |
| **Windows-Host** | winget `Syncthing.Syncthing` | Task Scheduler (autostart) | `windows-host.ps1` (REST API) |

### REST API Configuration

After the service starts, Syncthing is configured via its REST API:

1. Adds the Synology as a remote device (Device ID)
2. Creates the sync folder shared with the Synology

**macOS / Linux:** The Synology Device ID is read from 1Password at runtime:

```
syncthing_synology_op_ref: "op://Private/Syncthing-Synology/device-id"
```

Override per host in `machines.yml` if needed.

**Windows Host:** The configuration is read from `syncthing.txt` (see below).

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

The Windows bootstrap script (`windows-host.ps1`) automatically:
- Creates a Task Scheduler entry for autostart at logon
- Configures Syncthing via REST API (device + folder)

If WSL needs access to the synced folder, create a symlink via chezmoi:

```bash
# Example: link ~/Sync to the Windows sync folder
ln -s /mnt/c/Users/<username>/Sync ~/Sync
```

The exact path depends on your Windows Syncthing configuration.

### Windows Host: syncthing.txt

Create `syncthing.txt` in your config repo to configure Syncthing on Windows:

```
# syncthing.txt — Windows host Syncthing config
# Format: key = value (# = comment)

# Synology Device ID — find it in Synology Syncthing UI: Actions > Show ID
synology_device_id = XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX

# Folder ID — must match the folder ID on the Synology
folder_id   = sync-vault

# Folder path on Windows — supports environment variables
folder_path = %USERPROFILE%\Sync
```

| Key | Required | Description |
|-----|----------|-------------|
| `synology_device_id` | Yes* | Synology's Syncthing device ID |
| `folder_id` | Yes* | Folder ID (must match Synology) |
| `folder_path` | Yes* | Windows folder path (env vars supported) |

*If `synology_device_id` is missing, device/folder configuration is skipped.
Autostart is still set up, allowing manual configuration via the Syncthing GUI.

### Windows Host: Autostart

The bootstrap creates a Task Scheduler task named `rocket-launch-syncthing`:
- Runs at user logon
- Starts `syncthing.exe --no-browser` (headless, no GUI window)
- User-scope (no admin required, `-RunLevel Limited`)

To access the Syncthing web UI after autostart: `http://localhost:8384`

### Windows Host: First Run

On first bootstrap (Syncthing not yet installed or never run):

1. Syncthing is installed via winget (`Syncthing.Syncthing`)
2. The bootstrap starts Syncthing headless to generate `config.xml` and the API key
3. The autostart task is created
4. Synology device and sync folder are configured via REST API

After the bootstrap completes:
- [ ] Open `http://localhost:8384` to verify Syncthing is running
- [ ] Accept this device on your Synology Syncthing web UI
- [ ] The sync folder will start syncing after acceptance

## Windows Defaults (Registry Settings)

The `windows-defaults.txt` file contains Windows registry settings applied by
`bootstrap/windows-host.ps1`. This is the Windows counterpart to the `macos-defaults`
role (macOS system preferences).

### File Format

One setting per line, pipe-separated. Lines starting with `#` are comments.

```
<hive:\path>|<valueName>|<DWord|String>|<data>
```

Example:
```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt|DWord|0
```

### Included Settings

| Setting | Registry Value | Effect |
|---------|----------------|--------|
| Show taskbar on all monitors | `MMTaskbarEnabled = 1` | Taskbar visible on secondary monitors |
| Taskbar buttons per monitor | `MMTaskbarMode = 2` | Buttons appear only on the monitor where the window is (0 = all, 1 = main + current, 2 = only current) |
| Show file extensions | `HideFileExt = 0` | File extensions visible in Explorer |
| Show hidden files | `Hidden = 1` | Hidden files visible in Explorer |

All settings are under `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`.

### Behavior

- **Idempotent:** Only changed values are written; unchanged settings are skipped.
- **Explorer restart:** If any settings changed, Explorer is restarted once at the end
  (the shell briefly reloads). No restart if nothing changed.
- **Versionslos:** DWORD/String keys work identically on Windows 10 and Windows 11.
- **No admin required:** All settings are in HKCU (current user).

### Adding Custom Settings

Add lines to `windows-defaults.txt` following the pipe-separated format. Supported types:
- `DWord` — integer value (e.g., `0`, `1`, `2`)
- `String` — text value

Binary blobs and other types are not supported.

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
