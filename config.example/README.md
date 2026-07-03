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
| `profiles/*.yml` | Reusable bundles of logical package names. |
| `windows-host.txt` | winget ids for Windows host GUI apps. |
| `dotfiles/` | chezmoi source for your dotfiles (+ `op://` secret refs). |

## How resolution works

1. The engine looks up your **hostname** in `machines.yml` → list of profiles.
2. It unions the `packages:` from each profile.
3. Each logical name is resolved to the right manager via the engine's
   `lib/package-map.yml` (brew/cask, apt, dnf, flatpak; winget on the Windows host).

Add a new machine = one entry in `machines.yml`. Add a new app = add it to a
profile and ensure it exists in the engine `package-map.yml`.

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
