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

# --- Apply Windows Registry defaults (idempotent) ---
function Get-WindowsDefaults {
    param([string]$Repo)
    $tmp = Join-Path $env:TEMP ("rl-config-defaults-" + [guid]::NewGuid())
    git clone --depth 1 $Repo $tmp 2>$null | Out-Null
    $file = Join-Path $tmp "windows-defaults.txt"
    if (Test-Path $file) {
        $lines = Get-Content $file | Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } | ForEach-Object { $_.Trim() }
        if ($lines.Count -gt 0) { return $lines }
    }
    Write-Warn "No windows-defaults.txt in config repo — using built-in defaults."
    return @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|MMTaskbarEnabled|DWord|1",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|MMTaskbarMode|DWord|2",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt|DWord|0",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Hidden|DWord|1"
    )
}

function Set-WindowsDefault {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Type,
        [string]$Data
    )
    try {
        # Ensure registry key exists
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        # Determine target value based on type
        $targetValue = $Data
        if ($Type -eq "DWord") {
            $targetValue = [int]$Data
        }

        # Check current value (idempotent)
        $currentProperty = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $currentProperty) {
            $currentValue = $currentProperty.$Name
            if ($currentValue -eq $targetValue) {
                Write-Host "    $Name already set to $Data" -ForegroundColor Gray
                return $false
            }
        }

        # Set the registry value
        if ($Type -eq "DWord") {
            Set-ItemProperty -Path $Path -Name $Name -Value $targetValue -Type DWord
        }
        else {
            Set-ItemProperty -Path $Path -Name $Name -Value $targetValue -Type String
        }
        Write-Ok "$Name = $Data"
        return $true
    }
    catch {
        Write-Warn "Failed to set $Path\$Name`: $($_.Exception.Message)"
        return $false
    }
}

Write-Step "Applying Windows defaults (registry)..."
$defaultLines = Get-WindowsDefaults -Repo $Config
$changedCount = 0

foreach ($line in $defaultLines) {
    $parts = $line.Split("|")
    if ($parts.Count -lt 4) {
        Write-Warn "Skipping malformed line: $line"
        continue
    }
    $regPath = $parts[0].Trim()
    $regName = $parts[1].Trim()
    $regType = $parts[2].Trim()
    $regData = $parts[3].Trim()

    if ([string]::IsNullOrWhiteSpace($regPath) -or [string]::IsNullOrWhiteSpace($regName)) {
        Write-Warn "Skipping line with empty path or name: $line"
        continue
    }

    if ($regType -ne "DWord" -and $regType -ne "String") {
        Write-Warn "Unsupported type '$regType' in: $line"
        continue
    }

    $changed = Set-WindowsDefault -Path $regPath -Name $regName -Type $regType -Data $regData
    if ($changed) {
        $changedCount++
    }
}

# Restart Explorer only if changes were made
if ($changedCount -gt 0) {
    Write-Step "Restarting Explorer to apply changes (shell will briefly reload)..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Write-Ok "Explorer restarted — $changedCount setting(s) applied."
}
else {
    Write-Host "    No registry changes needed." -ForegroundColor Gray
}

Write-Step "Windows host provisioning complete."
