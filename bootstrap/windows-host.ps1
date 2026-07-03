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

# --- Syncthing configuration (REST-API, autostart) ---
# Reads syncthing.txt from config repo and configures:
# - Autostart via Task Scheduler
# - Synology device pairing
# - Sync folder creation

function Get-SyncthingConfig {
    param([string]$Repo)
    $result = @{
        synology_device_id = $null
        folder_id          = $null
        folder_path        = $null
    }
    $tmp = Join-Path $env:TEMP ("rl-config-syncthing-" + [guid]::NewGuid())
    git clone --depth 1 $Repo $tmp 2>$null | Out-Null
    $file = Join-Path $tmp "syncthing.txt"
    if (-not (Test-Path $file)) {
        return $result
    }
    $lines = Get-Content $file | Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") }
    foreach ($line in $lines) {
        if ($line -match "^\s*(\w+)\s*=\s*(.+)\s*$") {
            $key = $Matches[1].Trim().ToLower()
            $value = $Matches[2].Trim()
            switch ($key) {
                "synology_device_id" { $result.synology_device_id = $value }
                "folder_id"          { $result.folder_id = $value }
                "folder_path"        { $result.folder_path = $value }
            }
        }
    }
    return $result
}

function Get-SyncthingExePath {
    # Try to find syncthing.exe via Get-Command first
    $cmd = Get-Command syncthing.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    # Fallback: typical winget installation paths
    $possiblePaths = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\syncthing.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Syncthing\syncthing.exe"),
        (Join-Path $env:ProgramFiles "Syncthing\syncthing.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Syncthing\syncthing.exe")
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Get-SyncthingApiKey {
    # Primary path for Syncthing on Windows
    $configPath = Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"
    if (-not (Test-Path $configPath)) {
        # Syncthing v2 might use a different path — check common alternatives
        $altPath = Join-Path $env:APPDATA "Syncthing\config.xml"
        if (Test-Path $altPath) {
            $configPath = $altPath
        }
        else {
            return $null
        }
    }
    try {
        [xml]$configXml = Get-Content $configPath
        $apiKey = $configXml.configuration.gui.apikey
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            return $null
        }
        return $apiKey
    }
    catch {
        Write-Warn "Failed to parse Syncthing config.xml: $($_.Exception.Message)"
        return $null
    }
}

function Test-SyncthingApi {
    param(
        [string]$ApiKey,
        [string]$BaseUrl = "http://127.0.0.1:8384"
    )
    try {
        $headers = @{ "X-API-Key" = $ApiKey }
        $response = Invoke-RestMethod -Uri "$BaseUrl/rest/system/ping" -Headers $headers -TimeoutSec 5 -ErrorAction Stop
        return ($response.ping -eq "pong")
    }
    catch {
        return $false
    }
}

function Start-SyncthingHeadless {
    param([string]$ExePath)
    Write-Step "Starting Syncthing headless..."
    # Start syncthing in background, no browser, no restart
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $ExePath
    $pinfo.Arguments = "--no-browser --no-restart"
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($pinfo)
    # Give it a moment to initialize
    Start-Sleep -Seconds 2
    return $process
}

function Initialize-Syncthing {
    param([string]$ExePath)

    # First, check if we already have a valid API key
    $apiKey = Get-SyncthingApiKey
    if ($apiKey -and (Test-SyncthingApi -ApiKey $apiKey)) {
        Write-Ok "Syncthing API is already reachable"
        return $apiKey
    }

    # Need to start Syncthing — this may be the first run (creates config.xml)
    if (-not $ExePath) {
        Write-Warn "syncthing.exe not found — cannot start Syncthing"
        return $null
    }

    $process = Start-SyncthingHeadless -ExePath $ExePath
    if (-not $process) {
        Write-Warn "Failed to start Syncthing process"
        return $null
    }

    # Wait for config.xml to be created (first run) and API to become available
    $maxRetries = 15
    $retryDelay = 2
    for ($i = 1; $i -le $maxRetries; $i++) {
        $apiKey = Get-SyncthingApiKey
        if ($apiKey -and (Test-SyncthingApi -ApiKey $apiKey)) {
            Write-Ok "Syncthing API is now reachable (attempt $i/$maxRetries)"
            return $apiKey
        }
        Write-Host "    Waiting for Syncthing API... ($i/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds $retryDelay
    }

    Write-Warn "Syncthing API did not become reachable after $($maxRetries * $retryDelay) seconds"
    return $null
}

function Set-SyncthingAutostart {
    param([string]$ExePath)
    $taskName = "rocket-launch-syncthing"

    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "    Task '$taskName' already exists — skipping" -ForegroundColor Gray
        return $true
    }

    Write-Step "Creating Syncthing autostart task..."
    try {
        $action = New-ScheduledTaskAction -Execute $ExePath -Argument "--no-browser"
        $trigger = New-ScheduledTaskTrigger -AtLogon
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
        Write-Ok "Created autostart task '$taskName'"
        return $true
    }
    catch {
        Write-Warn "Failed to create autostart task: $($_.Exception.Message)"
        return $false
    }
}

function Get-SyncthingLocalDeviceId {
    param(
        [string]$ApiKey,
        [string]$BaseUrl = "http://127.0.0.1:8384"
    )
    try {
        $headers = @{ "X-API-Key" = $ApiKey }
        $status = Invoke-RestMethod -Uri "$BaseUrl/rest/system/status" -Headers $headers -TimeoutSec 10
        return $status.myID
    }
    catch {
        Write-Warn "Failed to get local device ID: $($_.Exception.Message)"
        return $null
    }
}

function Set-SyncthingDevice {
    param(
        [string]$ApiKey,
        [string]$DeviceId,
        [string]$DeviceName,
        [string]$BaseUrl = "http://127.0.0.1:8384"
    )
    try {
        $headers = @{
            "X-API-Key"    = $ApiKey
            "Content-Type" = "application/json"
        }

        # Check if device already exists
        $devices = Invoke-RestMethod -Uri "$BaseUrl/rest/config/devices" -Headers $headers -TimeoutSec 10
        $existingDevice = $devices | Where-Object { $_.deviceID -eq $DeviceId }
        if ($existingDevice) {
            Write-Host "    Device '$DeviceName' ($DeviceId) already configured — skipping" -ForegroundColor Gray
            return $true
        }

        # Add new device. addresses=dynamic matches the Linux/macOS role (RL-15)
        # and lets Syncthing discover the peer; other fields default sensibly.
        $deviceConfig = @{
            deviceID  = $DeviceId
            name      = $DeviceName
            addresses = @("dynamic")
        }
        $body = $deviceConfig | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri "$BaseUrl/rest/config/devices" -Method Post -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
        Write-Ok "Added device '$DeviceName'"
        return $true
    }
    catch {
        Write-Warn "Failed to add device '$DeviceName': $($_.Exception.Message)"
        return $false
    }
}

function Set-SyncthingFolder {
    param(
        [string]$ApiKey,
        [string]$FolderId,
        [string]$FolderPath,
        [string]$LocalDeviceId,
        [string]$RemoteDeviceId,
        [string]$BaseUrl = "http://127.0.0.1:8384"
    )
    try {
        $headers = @{
            "X-API-Key"    = $ApiKey
            "Content-Type" = "application/json"
        }

        # Check if folder already exists
        $folders = Invoke-RestMethod -Uri "$BaseUrl/rest/config/folders" -Headers $headers -TimeoutSec 10
        $existingFolder = $folders | Where-Object { $_.id -eq $FolderId }
        if ($existingFolder) {
            Write-Host "    Folder '$FolderId' already configured — skipping" -ForegroundColor Gray
            return $true
        }

        # Expand environment variables in path (e.g., %USERPROFILE%\Sync)
        $expandedPath = [Environment]::ExpandEnvironmentVariables($FolderPath)

        # Ensure folder directory exists
        if (-not (Test-Path $expandedPath)) {
            New-Item -ItemType Directory -Path $expandedPath -Force | Out-Null
            Write-Host "    Created folder directory: $expandedPath" -ForegroundColor Gray
        }

        # Build device list (local + remote)
        $deviceList = @(
            @{ deviceID = $LocalDeviceId }
        )
        if ($RemoteDeviceId) {
            $deviceList += @{ deviceID = $RemoteDeviceId }
        }

        # Add new folder
        $folderConfig = @{
            id      = $FolderId
            label   = $FolderId
            path    = $expandedPath
            type    = "sendreceive"
            devices = $deviceList
        }
        $body = $folderConfig | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri "$BaseUrl/rest/config/folders" -Method Post -Headers $headers -Body $body -TimeoutSec 10 | Out-Null
        Write-Ok "Added folder '$FolderId' at $expandedPath"
        return $true
    }
    catch {
        Write-Warn "Failed to add folder '$FolderId': $($_.Exception.Message)"
        return $false
    }
}

# --- Main Syncthing configuration flow ---
Write-Step "Configuring Syncthing..."

$syncthingExe = Get-SyncthingExePath
if (-not $syncthingExe) {
    Write-Warn "Syncthing not installed — skipping configuration. Install via winget: Syncthing.Syncthing"
}
else {
    Write-Host "    Found syncthing.exe at: $syncthingExe" -ForegroundColor Gray

    # Set up autostart regardless of config file presence
    Set-SyncthingAutostart -ExePath $syncthingExe | Out-Null

    # Read config from config repo
    $stConfig = Get-SyncthingConfig -Repo $Config

    # Ensure Syncthing is running and get API key
    $apiKey = Initialize-Syncthing -ExePath $syncthingExe

    if (-not $apiKey) {
        Write-Warn "Could not obtain Syncthing API key — skipping REST configuration"
    }
    elseif (-not $stConfig.synology_device_id) {
        Write-Warn "No synology_device_id in syncthing.txt — skipping device/folder configuration"
        Write-Host "    To enable: add 'synology_device_id = <your-synology-device-id>' to syncthing.txt" -ForegroundColor Gray
        Write-Host "    After configuration, accept this device on the Synology Syncthing web UI" -ForegroundColor Gray
    }
    else {
        # Get local device ID
        $localDeviceId = Get-SyncthingLocalDeviceId -ApiKey $apiKey
        if (-not $localDeviceId) {
            Write-Warn "Could not obtain local device ID — skipping REST configuration"
        }
        else {
            Write-Host "    Local device ID: $($localDeviceId.Substring(0, 7))..." -ForegroundColor Gray

            # Add Synology device
            Set-SyncthingDevice -ApiKey $apiKey -DeviceId $stConfig.synology_device_id -DeviceName "Synology" | Out-Null

            # Add sync folder (if configured)
            if ($stConfig.folder_id -and $stConfig.folder_path) {
                Set-SyncthingFolder -ApiKey $apiKey -FolderId $stConfig.folder_id -FolderPath $stConfig.folder_path -LocalDeviceId $localDeviceId -RemoteDeviceId $stConfig.synology_device_id | Out-Null
            }
            else {
                Write-Warn "folder_id or folder_path not configured in syncthing.txt — skipping folder setup"
            }

            Write-Ok "Syncthing configuration complete"
            Write-Host "    IMPORTANT: Accept this device on your Synology Syncthing web UI to complete pairing" -ForegroundColor Yellow
        }
    }
}

Write-Step "Windows host provisioning complete."
