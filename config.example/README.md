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
