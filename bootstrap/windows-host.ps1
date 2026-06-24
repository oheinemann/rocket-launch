<#
.SYNOPSIS
    rocket-launch — Windows host app provisioning (winget).

.DESCRIPTION
    Installs GUI apps that live on the Windows host (not inside WSL): browser,
    Slack, 1Password, terminal, optionally an IDE. The app list is data-driven:
    it reads `windows-host.txt` from the config repo (one winget id per line,
    '#' comments allowed). winget is primary; choco is an optional fallback for
    ids prefixed with "choco:".

.PARAMETER Config
    Git URL of the config repo to read the host app list from.
#>
[CmdletBinding()]
param(
    [string]$Config = "https://github.com/oheinemann/rocket-launch-config.git"
)
$ErrorActionPreference = "Stop"

function Write-Step { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "!!! $m" -ForegroundColor Yellow }

function Assert-Winget {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) { return }
    Write-Warn "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    throw "winget is required."
}

function Install-WingetId {
    param([string]$Id)
    Write-Step "winget install $Id"
    winget install --id $Id --exact --silent --accept-package-agreements `
        --accept-source-agreements --disable-interactivity 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok "installed/upgraded $Id" }
    else { Write-Warn "winget returned $LASTEXITCODE for $Id" }
}

function Install-ChocoId {
    param([string]$Id)
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Write-Step "Installing Chocolatey (fallback)"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    Write-Step "choco install $Id"
    choco install $Id -y --no-progress | Out-Null
}

# --- Resolve the host app list from the config repo ---
function Get-HostApps {
    param([string]$Repo)
    $tmp = Join-Path $env:TEMP ("rl-config-" + [guid]::NewGuid())
    git clone --depth 1 $Repo $tmp 2>$null | Out-Null
    $file = Join-Path $tmp "windows-host.txt"
    if (Test-Path $file) {
        return Get-Content $file | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() }
    }
    Write-Warn "No windows-host.txt in config repo — using built-in defaults."
    return @(
        "Microsoft.WindowsTerminal",
        "AgileBits.1Password",
        "SlackTechnologies.Slack",
        "Mozilla.Firefox"
    )
}

# ----------------------------------------------------------------------------
Assert-Winget
$apps = Get-HostApps -Repo $Config
foreach ($app in $apps) {
    if ($app.StartsWith("choco:")) { Install-ChocoId ($app.Substring(6)) }
    else { Install-WingetId $app }
}
Write-Step "Windows host provisioning complete."
