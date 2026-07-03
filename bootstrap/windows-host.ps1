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

# --- Resolve Nerd Font list from config repo ---
function Get-FontList {
    param([string]$Repo)
    $tmp = Join-Path $env:TEMP ("rl-config-fonts-" + [guid]::NewGuid())
    git clone --depth 1 $Repo $tmp 2>$null | Out-Null
    $file = Join-Path $tmp "windows-fonts.txt"
    if (Test-Path $file) {
        $fonts = Get-Content $file | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() }
        if ($fonts.Count -gt 0) { return $fonts }
    }
    Write-Warn "No windows-fonts.txt in config repo — using built-in defaults."
    return @("JetBrainsMono", "FiraCode", "Meslo")
}

# --- Install Nerd Font (user-scope, no admin required) ---
# Downloads from GitHub releases, installs to LOCALAPPDATA\Microsoft\Windows\Fonts
# and registers in HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts.
function Install-NerdFont {
    param(
        [string]$FontName,
        [string]$Version = "v3.4.0"
    )
    $userFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

    # Ensure user fonts directory exists
    if (-not (Test-Path $userFontsDir)) {
        New-Item -ItemType Directory -Path $userFontsDir -Force | Out-Null
    }

    # Download URL
    $zipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$Version/$FontName.zip"
    $tempZip = Join-Path $env:TEMP "$FontName-nerd-$Version.zip"
    $tempExtract = Join-Path $env:TEMP ("nf-$FontName-" + [guid]::NewGuid())

    Write-Step "Installing Nerd Font: $FontName"

    try {
        # Download if not cached
        if (-not (Test-Path $tempZip)) {
            Write-Host "    Downloading $FontName.zip..."
            Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        }

        # Extract to temp
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        # Install each ttf file
        $ttfFiles = Get-ChildItem -Path $tempExtract -Filter "*.ttf" -Recurse
        $installedCount = 0
        $skippedCount = 0

        foreach ($ttf in $ttfFiles) {
            $destPath = Join-Path $userFontsDir $ttf.Name

            # Skip if already installed
            if (Test-Path $destPath) {
                $skippedCount++
                continue
            }

            # Copy font file
            Copy-Item -Path $ttf.FullName -Destination $destPath -Force

            # Get font name from file (use filename without extension as fallback)
            $fontDisplayName = [System.IO.Path]::GetFileNameWithoutExtension($ttf.Name)

            # Register in registry (user scope). Per-user fonts (HKCU) must store
            # the FULL path to the font file, unlike system fonts (HKLM) which use
            # just the filename resolved against %WINDIR%\Fonts.
            $regValueName = "$fontDisplayName (TrueType)"
            $existingValue = Get-ItemProperty -Path $regPath -Name $regValueName -ErrorAction SilentlyContinue
            if (-not $existingValue) {
                New-ItemProperty -Path $regPath -Name $regValueName -Value $destPath -PropertyType String -Force | Out-Null
            }

            $installedCount++
        }

        if ($installedCount -gt 0) {
            Write-Ok "Installed $installedCount font files for $FontName"
        }
        if ($skippedCount -gt 0) {
            Write-Host "    Skipped $skippedCount already installed" -ForegroundColor Gray
        }

        # Cleanup extract dir
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
    }
    catch {
        Write-Warn "Failed to install $FontName`: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------
Assert-Winget

# --- Install winget/choco apps ---
$apps = Get-HostApps -Repo $Config
foreach ($app in $apps) {
    if ($app.StartsWith("choco:")) { Install-ChocoId ($app.Substring(6)) }
    else { Install-WingetId $app }
}

# --- Install Nerd Fonts (user-scope) ---
Write-Step "Installing Nerd Fonts..."
$fonts = Get-FontList -Repo $Config
foreach ($font in $fonts) {
    Install-NerdFont -FontName $font
}

Write-Step "Windows host provisioning complete."
